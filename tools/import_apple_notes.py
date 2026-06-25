#!/usr/bin/env python3
"""
Apple Notes → Notex Importer
Reads all notes from Apple Notes via JXA, writes to Notex Core Data SQLite.
"""

import subprocess
import json
import sqlite3
import time
import os
import uuid as uuidlib
from datetime import datetime

DB_PATH = os.path.expanduser("~/Library/Application Support/Notex/NotexModel.sqlite")
BATCH_SIZE = 50  # notes per JXA call
NOTES_RESTART_INTERVAL = 200  # restart Notes.app every N notes

def run_jxa(script):
    """Run JavaScript for Automation script"""
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        print(f"  ⚠️ JXA error: {result.stderr[:200]}")
        return None
    return result.stdout.strip()

def get_note_count():
    """Get total note count"""
    script = '''
    const Notes = Application("Notes");
    Notes.notes.length;
    '''
    result = run_jxa(script)
    return int(result) if result else 0

def read_notes_batch(offset, limit):
    """Read a batch of notes via JXA — returns list of dicts"""
    script = f'''
    const Notes = Application("Notes");
    const notes = Notes.notes;
    const total = notes.length;
    const start = {offset};
    const end = Math.min(start + {limit}, total);
    const result = [];
    
    for (let i = start; i < end; i++) {{
        try {{
            const n = notes[i];
            const name = n.name();
            let plaintext = "";
            try {{ plaintext = n.plaintext(); }} catch(e) {{}}
            let creationDate = null;
            try {{ creationDate = n.creationDate().toISOString(); }} catch(e) {{}}
            let modificationDate = null;
            try {{ modificationDate = n.modificationDate().toISOString(); }} catch(e) {{}}
            let container = "";
            try {{ container = n.container().name(); }} catch(e) {{}}
            
            result.push({{
                name: name,
                plaintext: plaintext,
                creationDate: creationDate,
                modificationDate: modificationDate,
                container: container
            }});
        }} catch(e) {{
            // Skip broken notes
        }}
    }}
    JSON.stringify(result);
    '''
    result = run_jxa(script)
    if not result:
        return []
    try:
        return json.loads(result)
    except:
        print(f"  ⚠️ JSON parse error for batch {offset}")
        return []

def html_to_text(html):
    """Simple HTML to text conversion"""
    if not html:
        return ""
    import re
    text = html
    text = re.sub(r'<br\s*/?>', '\n', text)
    text = re.sub(r'<div[^>]*>', '\n', text)
    text = re.sub(r'</div>', '', text)
    text = re.sub(r'<p[^>]*>', '\n', text)
    text = re.sub(r'</p>', '', text)
    text = re.sub(r'<li[^>]*>', '• ', text)
    text = re.sub(r'</li>', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = text.replace('&amp;', '&')
    text = text.replace('&lt;', '<')
    text = text.replace('&gt;', '>')
    text = text.replace('&quot;', '"')
    text = text.replace('&#39;', "'")
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()

def date_to_coredata(date_str):
    """Convert ISO date to Core Data timestamp (seconds since 2001-01-01)"""
    if not date_str:
        return None
    try:
        dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        ref = datetime(2001, 1, 1, tzinfo=dt.tzinfo)
        return (dt - ref).total_seconds()
    except:
        return None

def write_to_coredata(notes_data):
    """Write notes to Notex Core Data SQLite"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Get entity IDs
    c.execute("SELECT Z_NAME, Z_ENT FROM Z_PRIMARYKEY")
    entities = dict(c.fetchall())
    note_ent = entities.get('Note', 2)
    tag_ent = entities.get('Tag', 4)
    notetag_ent = entities.get('NoteTag', 5)
    notebook_ent = entities.get('Notebook', 6)
    
    # Get max PKs
    c.execute("SELECT MAX(Z_PK) FROM ZNOTE")
    max_note_pk = c.fetchone()[0] or 0
    c.execute("SELECT MAX(Z_PK) FROM ZTAG")
    max_tag_pk = c.fetchone()[0] or 0
    c.execute("SELECT MAX(Z_PK) FROM ZNOTETAG")
    max_notetag_pk = c.fetchone()[0] or 0
    c.execute("SELECT MAX(Z_PK) FROM ZNOTEBOOK")
    max_notebook_pk = c.fetchone()[0] or 0
    
    # Track existing notebooks by name
    c.execute("SELECT Z_PK, ZNAME FROM ZNOTEBOOK")
    notebook_map = {}
    for row in c.fetchall():
        if row[1]:
            notebook_map[row[1]] = row[0]
    
    # Track existing tags by name
    c.execute("SELECT Z_PK, ZNAME FROM ZTAG")
    tag_map = {}
    for row in c.fetchall():
        if row[1]:
            tag_map[row[1]] = row[0]
    
    imported = 0
    now_cd = (datetime.now() - datetime(2001, 1, 1)).total_seconds()
    
    for note_data in notes_data:
        title = note_data.get('name', '').strip()
        if not title:
            title = 'Başlıksız Not'
        
        plaintext = note_data.get('plaintext', '')
        if not plaintext:
            plaintext = ''
        
        created = date_to_coredata(note_data.get('creationDate'))
        modified = date_to_coredata(note_data.get('modificationDate'))
        
        container = note_data.get('container', '').strip()
        
        # Find or create notebook
        notebook_pk = None
        if container:
            if container in notebook_map:
                notebook_pk = notebook_map[container]
            else:
                max_notebook_pk += 1
                notebook_pk = max_notebook_pk
                c.execute(
                    "INSERT INTO ZNOTEBOOK (Z_PK, Z_ENT, Z_OPT, ZNAME, ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, 1, ?, ?, ?)",
                    (notebook_pk, notebook_ent, container, now_cd, now_cd)
                )
                notebook_map[container] = notebook_pk
        
        # Create note
        max_note_pk += 1
        note_pk = max_note_pk
        note_uuid = str(uuidlib.uuid4())
        
        c.execute("""INSERT INTO ZNOTE 
            (Z_PK, Z_ENT, Z_OPT, ZTITLE, ZPLAINTEXT, ZCREATEDAT, ZUPDATEDAT, ZUUID,
             ZISFAVORITE, ZISTRASHED, ZISARCHIVED, ZNOTEBOOK)
            VALUES (?, ?, 1, ?, ?, ?, ?, ?, 0, 0, 0, ?)""",
            (note_pk, note_ent, title, plaintext[:50000], created or now_cd, modified or now_cd, note_uuid, notebook_pk))
        
        # Extract tags from plaintext (#hashtag pattern)
        import re
        tags = re.findall(r'#(\w+)', plaintext)
        for tag_name in set(tags[:5]):  # Max 5 tags per note
            tag_name = tag_name.strip()
            if not tag_name or len(tag_name) > 30:
                continue
            if tag_name in tag_map:
                tag_pk = tag_map[tag_name]
            else:
                max_tag_pk += 1
                tag_pk = max_tag_pk
                c.execute(
                    "INSERT INTO ZTAG (Z_PK, Z_ENT, Z_OPT, ZNAME, ZCREATEDAT) VALUES (?, ?, 1, ?, ?)",
                    (tag_pk, tag_ent, tag_name, now_cd)
                )
                tag_map[tag_name] = tag_pk
            
            max_notetag_pk += 1
            c.execute(
                "INSERT INTO ZNOTETAG (Z_PK, Z_ENT, Z_OPT, ZNOTE, ZTAG) VALUES (?, ?, 1, ?, ?)",
                (max_notetag_pk, notetag_ent, note_pk, tag_pk)
            )
        
        imported += 1
    
    conn.commit()
    conn.close()
    return imported

def restart_notes():
    """Restart Notes.app to prevent hangs"""
    subprocess.run(["killall", "Notes"], capture_output=True)
    time.sleep(3)
    subprocess.run(["open", "-a", "Notes"], capture_output=True)
    time.sleep(5)

def main():
    print("🍎 Apple Notes → Notex Import Aracı")
    print("=" * 50)
    
    # Check database exists
    if not os.path.exists(DB_PATH):
        print(f"❌ Notex veritabanı bulunamadı: {DB_PATH}")
        print("   Önce Notex uygulamasını en az bir kez açın.")
        return
    
    # Get note count
    print("\n📊 Apple Notes not sayısı alınıyor...")
    total = get_note_count()
    print(f"   {total} not bulundu")
    
    if total == 0:
        print("   İçe aktarılacak not yok.")
        return
    
    # Import in batches
    print(f"\n🚀 İçe aktarım başlıyor (batch size: {BATCH_SIZE})...")
    
    total_imported = 0
    batch_num = 0
    notes_since_restart = 0
    start_time = time.time()
    
    for offset in range(0, total, BATCH_SIZE):
        batch_num += 1
        batch_end = min(offset + BATCH_SIZE, total)
        
        # Read batch
        print(f"\n  [{batch_num}] Notlar {offset+1}-{batch_end} okunuyor...", end="", flush=True)
        batch_start_time = time.time()
        notes = read_notes_batch(offset, BATCH_SIZE)
        read_time = time.time() - batch_start_time
        print(f" {len(notes)} not ({read_time:.1f}s)")
        
        if not notes:
            print(f"  ⚠️ Batch {batch_num} boş, atlanıyor")
            continue
        
        # Write to Core Data
        count = write_to_coredata(notes)
        total_imported += count
        notes_since_restart += count
        
        elapsed = time.time() - start_time
        rate = total_imported / max(1, elapsed)
        remaining = (total - offset - BATCH_SIZE) / max(1, rate)
        print(f"  ✅ {total_imported}/{total} not içe aktarıldı ({rate:.1f} not/sn, ~{remaining/60:.1f} dk kaldı)")
        
        # Restart Notes.app periodically
        if notes_since_restart >= NOTES_RESTART_INTERVAL:
            print(f"  🔄 Notes.app yeniden başlatılıyor ({notes_since_restart} not)...")
            restart_notes()
            notes_since_restart = 0
    
    elapsed = time.time() - start_time
    print(f"\n{'=' * 50}")
    print(f"✅ İçe aktarım tamamlandı!")
    print(f"   Toplam: {total_imported} not")
    print(f"   Süre: {elapsed:.1f} saniye ({elapsed/60:.1f} dakika)")
    print(f"   Hız: {total_imported/max(1,elapsed):.1f} not/sn")
    
    # Verify
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM ZNOTE")
    total_notes = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM ZNOTEBOOK")
    total_notebooks = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM ZTAG")
    total_tags = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM ZNOTETAG")
    total_notetags = c.fetchone()[0]
    conn.close()
    
    print(f"\n📊 Notex veritabanı:")
    print(f"   Notlar: {total_notes}")
    print(f"   Defterler: {total_notebooks}")
    print(f"   Etiketler: {total_tags}")
    print(f"   Not-Etiket bağlantıları: {total_notetags}")
    print(f"\n💡 Notex uygulamasını yeniden açın (⌘Q → tekrar açın)")

if __name__ == "__main__":
    main()
