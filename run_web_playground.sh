#!/bin/bash
set -e

# You can use an alternative swift-build binary (e.g. one's you've built yourself)
# by providing a path to the swift-build binary as the first argument to this script.

PORT=${PORT:-8000}
bash ./build_web_playground.sh $1 $2
echo
echo "Web playground hosted at http://localhost:$PORT/index.html"
echo
cd static
python3 -m http.server $PORT
