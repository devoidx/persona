# Static check of every trait phrasing in Traits.lua: five phrasings per trait,
# and each phrasing only uses placeholders its add(...) call supplies
# ({name} and {his} are always supplied). Also flags a repeated unit word.
import re, sys
src = open(sys.argv[1]).read()
copy = src[src.index("local COPY = {"):src.index("\n}\n", src.index("local COPY = {"))]
traits = {}
for m in re.finditer(r'\n  (\w+) = \{\n    label = "[^"]+",\n    epithet = "([^"]*)",\n    lines = \{\n(.*?)\n    \},', copy, re.S):
    traits[m.group(1)] = (m.group(2), re.findall(r'^      "(.*)",$', m.group(3), re.M))

supplied = {}
for m in re.finditer(r'add\("(\w+)",[^{]*\{([^}]*)\}', src):
    supplied.setdefault(m.group(1), set()).update(re.findall(r'(\w+)\s*=', m.group(2)))
# Signature moves are added from the MOVE_TRAITS table with { n = ... }
mt = re.search(r"local MOVE_TRAITS = \{(.*?)\n  \}", src, re.S)
if mt:
    for tid in re.findall(r'\{ "(\w+)", "\w+", \d+ \}', mt.group(1)):
        supplied.setdefault(tid, set()).add("n")
# lifetime() fills in n itself
for m in re.finditer(r'lifetime\("(\w+)"', src):
    supplied.setdefault(m.group(1), set()).add("n")

problems = []
for tid, (epithet, lines) in traits.items():
    if tid not in supplied:
        problems.append(f"{tid}: never added in Build()")
        continue
    keys = supplied[tid] | {"name", "his"}
    if len(lines) != 5:
        problems.append(f"{tid}: {len(lines)} phrasings, expected 5")
    for text in lines + [epithet]:
        for ph in re.findall(r"\{(\w+)\}", text):
            if ph not in keys:
                problems.append(f"{tid}: {{{ph}}} not supplied in: {text}")
        for unit in ("minute", "hours", "yards", "seconds"):
            if len(re.findall(r"\b" + unit + r"\b", text)) > 1:
                problems.append(f"{tid}: '{unit}' repeated: {text}")
# Race and class flavour lines: same placeholder rules as the trait they belong to
fl = re.search(r"\nlocal FLAVOUR = \{\n(.*?)\n\}\n", src, re.S)
flavour = 0
if fl:
    for m in re.finditer(r'^  (\w+) = \{\n(.*?)\n  \},', fl.group(1), re.S | re.M):
        tid = m.group(1)
        if tid not in traits:
            problems.append(f"flavour for unknown trait {tid}")
            continue
        keys = supplied.get(tid, set()) | {"name", "his"}
        seen = set()
        for who, text in re.findall(r'^    (\w+) = "(.*)",$', m.group(2), re.M):
            flavour += 1
            if who in seen:
                problems.append(f"{tid}: two flavour lines for {who}")
            seen.add(who)
            for ph in re.findall(r"\{(\w+)\}", text):
                if ph not in keys:
                    problems.append(f"{tid} ({who}): {{{ph}}} not supplied in: {text}")
            for unit in ("minute", "hours", "yards", "seconds"):
                if len(re.findall(r"\b" + unit + r"\b", text)) > 1:
                    problems.append(f"{tid} ({who}): '{unit}' repeated: {text}")
assert not problems, "\n".join(problems)
print(f"ok: {len(traits)} traits, {sum(len(l) for _, l in traits.values())} phrasings, {flavour} race/class lines, every placeholder supplied")
