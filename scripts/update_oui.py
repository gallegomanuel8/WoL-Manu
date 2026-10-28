#!/usr/bin/env python3
"""
Regenera "WoL Manu/oui.txt", la base de datos de fabricantes por MAC (OUI)
que usa el analizador de red.

Fuente: lista `manuf` de Wireshark, generada a partir de los registros públicos
del IEEE (MA-L /24, MA-M /28 y MA-S /36). Se descarga de Wireshark porque el
servidor del IEEE rechaza descargas automatizadas.

Formato de salida, una entrada por línea:  <prefijo hex>/<bits>\t<fabricante>
    7085C2/24\tASRock

Uso:
    python3 scripts/update_oui.py
"""

import os
import re
import sys
import urllib.request

SOURCE_URL = "https://www.wireshark.org/download/automated/data/manuf"
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "WoL Manu", "oui.txt")

# Sufijos societarios que no aportan nada en la tabla
LEGAL_SUFFIX = re.compile(
    r"[,.\s]+(inc|incorporated|incorporation|corp|corporation|co|company|ltd|limited|"
    r"llc|l\.l\.c|gmbh|ag|sa|s\.a|s\.p\.a|spa|bv|b\.v|oy|ab|as|plc|pty|kg|srl|s\.r\.l|"
    r"pte|sdn\s+bhd|bhd|kk|k\.k|nv|n\.v)\.?$",
    re.IGNORECASE,
)


def clean(name):
    name = " ".join(name.split()).strip(" ,.")
    # Quitar sufijos repetidamente: "Foo Co., Ltd." -> "Foo"
    while True:
        shorter = LEGAL_SUFFIX.sub("", name).strip(" ,.")
        if shorter == name or not shorter:
            break
        name = shorter
    return name


def main():
    print(f"Descargando {SOURCE_URL} …")
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "WoL-Manu-OUI-updater"})
    with urllib.request.urlopen(request, timeout=120) as response:
        text = response.read().decode("utf-8", errors="replace")

    entries = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in line.split("\t") if f.strip()]
        if len(fields) < 2:
            continue
        prefix, _, bits = fields[0].partition("/")
        bits = int(bits) if bits else 24
        hex_prefix = prefix.replace(":", "").replace("-", "").upper()[: bits // 4]
        if len(hex_prefix) != bits // 4:
            continue
        name = clean(fields[2] if len(fields) > 2 else fields[1])
        if name:
            entries[f"{hex_prefix}/{bits}"] = name

    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("# Fabricantes por prefijo MAC. Generado por scripts/update_oui.py — no editar a mano.\n")
        for key in sorted(entries):
            f.write(f"{key}\t{entries[key]}\n")

    print(f"{len(entries)} entradas escritas en {os.path.normpath(OUTPUT)}")


if __name__ == "__main__":
    sys.exit(main())
