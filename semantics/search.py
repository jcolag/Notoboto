import inspect, json, os, re, requests, sqlite3, sqlite_vec, struct, sys
from ollama import chat, ChatResponse, Client
from typing import List

def serialize_f32(vector: List[float]) -> bytes:
    return struct.pack("%sf" % len(vector), *vector)

def js_r(path: str):
  filename = os.path.expanduser(path)
  with open(filename) as f_in:
    return json.load(f_in)

_ = sys.argv.pop(0)
query = ' '.join(sys.argv)
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

response: ChatResponse = client.embed(
  model = 'snowflake-arctic-embed2:latest',
  input = query
)

vec = (
  serialize_f32(response.embeddings[0]),
)

for row in db.execute(
  'SELECT path, line, distance FROM s2 WHERE vector MATCH ? AND k = 5 ORDER BY distance;',
  vec
):
  print(row)

db.close()

