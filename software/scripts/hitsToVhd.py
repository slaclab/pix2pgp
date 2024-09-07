import json
import re

# name of file subject to change
with open('dat.json') as f:
    hitMap = json.load(f)

hitDistro = []

# append hits into hit-distribution array
for hitIndex in range(len(hitMap)):
    _thisHit = hitMap.get(str(hitIndex))
    hitDistro.append((re.findall(r'\d+', _thisHit)))

clkWait = 186

vhdDump = open("stimuli.vhd", "w")

for eventIndex in range(len(hitDistro)):
    print(f"  ----------------------------------------", file=vhdDump)
    print(f"  --------------- hit = {eventIndex} ---------------", file=vhdDump)
    print(f"  ----------------------------------------", file=vhdDump)
    print(f"  wait for CLK_PERIOD_C*{str(clkWait)};", file=vhdDump)
    _thisEvent = hitDistro[eventIndex]
    for colIndex in range(len(_thisEvent)):

        _thisHit = _thisEvent[colIndex]
        print(f"    hitLen({colIndex}) <= toSlv({_thisHit}, hitLen(0)'length);", file=vhdDump)

    print("    sro <= '1';", file=vhdDump)
    print(f"  wait for CLK_PERIOD_C*2;", file=vhdDump)
    print("    sro <= '0';", file=vhdDump)
    print(f"  ----------------------------------------", file=vhdDump)
    print(f"  ----------------------------------------", file=vhdDump)
    print("\n", file=vhdDump)

vhdDump.close()
