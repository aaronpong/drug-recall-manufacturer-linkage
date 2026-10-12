import requests

url = "https://api.fda.gov/drug/enforcement.json"
r = requests.get(url, params={"limit": 1})
r.raise_for_status()

data = r.json()
print("Total recall records:", data["meta"]["results"]["total"])
print("Fields in one record:")
for key in data["results"][0].keys():
    print(" ", key)