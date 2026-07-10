import inspect, json, os, pprint
import pygit2
import sqlite3

def js_r(path: str):
  filename = os.path.expanduser(path)
  with open(filename) as f_in:
    return json.load(f_in)

def setup_db(cursor: sqlite3.Cursor):
  return None

config = js_r("~/.config/Miniboost.json")
location = config.get("location")
location = os.path.expanduser(location)

db = sqlite3.connect("semantic.db")
cursor = db.cursor()

opts = {
    "flags": pygit2.GIT_DIFF_INCLUDE_UNTRACKED |
             pygit2.GIT_DIFF_RECURSE_UNTRACKED_DIRS |
             pygit2.GIT_DIFF_IGNORE_WHITESPACE,
    "context_lines": 10**9
}
repo = pygit2.Repository(location)
index_tree_id = repo.index.write_tree()
index_tree = repo[index_tree_id]
diff = repo.diff(index_tree, None, **opts)

setup_db(cursor)
#results = cursor.execute("SELECT * FROM lines")
#pprint.pprint({k: getattr(results, k) for k in dir(results) if not k.startswith('_')})

diff.find_similar(
  flags=pygit2.GIT_DIFF_FIND_RENAMES
    | pygit2.GIT_DIFF_FIND_FOR_UNTRACKED
    | pygit2.GIT_DIFF_FIND_AND_BREAK_REWRITES
    | pygit2.GIT_DIFF_FIND_RENAMES_FROM_REWRITES
)

for patch in diff:
  print(patch.delta.old_file.path, " -> ", patch.delta.new_file.path)
  old_path = patch.delta.old_file.path
  new_path = patch.delta.new_file.path
  status   = patch.delta.status

  for hunk in patch.hunks:
    old_line = hunk.old_start
    new_line = hunk.new_start
    for line in hunk.lines:
      if line.origin == "-":
        old_line += 1
      elif line.origin == "+":
        new_line += 1
      else:
        old_line += 1
        new_line += 1
      if line.old_lineno != line.new_lineno and line.content.strip() != "":
        print("  ", line.old_lineno, " ~> ", line.new_lineno)

# pprint.pprint({k: getattr(line, k) for k in dir(line) if not k.startswith('_')})

#cursor.commit()
db.close()

