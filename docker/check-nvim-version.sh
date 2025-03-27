#!/bin/bash

cd "$(dirname "$0")"
docker build -t doit-plugin-test .
docker run --rm doit-plugin-test nvim --version