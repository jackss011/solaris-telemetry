echo "Running the software..."

mkdir -p build
./bin/odin/odin.exe run ./src -out:build/solaris.exe -resource:src/app.rc