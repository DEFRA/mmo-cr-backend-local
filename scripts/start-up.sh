#!/bin/bash
 
git submodule foreach '
if [ -f ".env.sample" ]; then
cp .env.sample .env
echo "Copied $name/.env.sample -> $name/.env"
else
touch .env
echo "Created empty file: $name/.env (no .env.sample found)"
fi
'
docker compose up --build -d 
