#!/bin/bash
# Post-edit hook: verifica que archivos Swift editados tengan sintaxis valida
# Solo valida si el archivo editado es .swift

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Solo verificar archivos Swift
if [[ "$FILE_PATH" != *.swift ]]; then
    exit 0
fi

# Verificar que el archivo existe
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Verificar sintaxis basica: parentesis/llaves balanceados
OPEN_BRACES=$(grep -o '{' "$FILE_PATH" | wc -l)
CLOSE_BRACES=$(grep -o '}' "$FILE_PATH" | wc -l)

if [[ "$OPEN_BRACES" -ne "$CLOSE_BRACES" ]]; then
    echo "Llaves desbalanceadas en $FILE_PATH: { = $OPEN_BRACES, } = $CLOSE_BRACES" >&2
    exit 2
fi

exit 0
