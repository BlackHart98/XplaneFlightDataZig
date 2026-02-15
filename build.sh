zig build

python -m venv env

# Activate virtual environment if it exists
if [ -d "env" ]; then
    source env/bin/activate
fi

pip install -r requirements.txt