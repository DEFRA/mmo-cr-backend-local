#!/bin/bash
 
for dir in mm-cr-*/; do
[ -d "$dir" ] || continue
 
if [ -f "${dir}.env.sample" ]; then
cp "${dir}.env.sample" "${dir}.env"
echo "Copied ${dir}.env.sample -> ${dir}.env"
else
touch "${dir}.env"
echo "Created empty file: ${dir}.env (no .env.sample found)"
fi
done
 
docker compose up --build -d
