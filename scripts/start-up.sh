#!/bin/bash

# Prevents the literal "mm-cr-*/" string if no folders match
shopt -s nullglob

echo "hello"

for dir in mmo-cr-*/; do
  echo "${dir} do exist"
  # Remove trailing slash for cleaner variable usage
  dir=${dir%/}
  

  # CORRECTED PATH: Look INSIDE the directory using ${dir}/.env.sample
  if [ -f "${dir}/.env.sample" ]; then
    cp "${dir}/.env.sample" "${dir}/.env"
    echo "Copied ${dir}/.env.sample -> ${dir}/.env"
  else
    touch "${dir}/.env"
    echo "Created empty file: ${dir}/.env (no .env.sample found)"
  fi
done

# docker compose up --build -d
