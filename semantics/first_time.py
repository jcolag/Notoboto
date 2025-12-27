import inspect, json, os, re, requests, sqlite3, sqlite_vec, struct, sys
from ollama import chat, ChatResponse, Client
from typing import List

def serialize_f32(vector: List[float]) -> bytes:
    return struct.pack("%sf" % len(vector), *vector)

def js_r(path: str):
  filename = os.path.expanduser(path)
  with open(filename) as f_in:
    return json.load(f_in)

cfg_name = os.path.join('~', '.config', 'Miniboost.json')
config = js_r(cfg_name)
location = config.get('location')
location = os.path.expanduser(location)
embedder = config.get('embedder')
note_path = os.path.join(location, 'notes')
note_dir = os.fsencode(note_path)
db = sqlite3.connect('semantic.db')
client = Client(
  host = embedder
)

db.enable_load_extension(True)
sqlite_vec.load(db)
db.enable_load_extension(False)

# res = cur.execute("SELECT semantics FROM sqlite_master")
# if res.fetchone() is None:
#   db.execute('CREATE TABLE semantics (path TEXT, line INTEGER, vector FLOAT[1024])')

try:
  db.execute('CREATE TABLE semantics (path TEXT, line INTEGER, vector FLOAT[1024])')
except Exception:
  print()

for file in os.listdir(note_dir):
  filename = os.fsdecode(file)
  file_path = os.path.join(note_path, filename)
  path = os.path.join('notes', filename)
  file_db = db.execute(
    'SELECT line FROM semantics WHERE path = ?',
    (path,)
  ).fetchall()
  if len(file_db):
    continue
  data = []
  print(file)
  with open(file_path) as f:
    lines = f.readlines()
    for ll, line in enumerate(lines):
      rx = re.compile('[^a-zA-Z]')
      letters = rx.sub('', line)
      if len(letters) <= 40:
        continue
      line = line.strip()
      response: ChatResponse = client.embed(
        model = 'snowflake-arctic-embed2:latest',
        input = line
      )
      data_line = (
        path,
        ll,
        serialize_f32(response.embeddings[0]),
      )
      data.append(data_line)
      print(ll, ' / ', len(lines))
    db.executemany(
      'INSERT INTO semantics(path, line, vector) VALUES (?, ?, ?);',
      data
    )
    db.commit()

#select
#  rowid,
#  distance
#from vec_examples
#where sample_embedding match '[0.890, 0.544, 0.825, 0.961, 0.358, 0.0196, 0.521, 0.175]'
#and k = 2
#order by distance
#limit 2;

db.commit()
db.close()

