SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/../../helper.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

CLIENT=clickhouse-client

if [ $1 ]; then
	PORT=$1
else
	PORT=9000
fi

if [ ! -f "hits.tsv" ]; then
	echo "Download test database..."
    wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz'
    gzip -d hits.tsv.gz
fi


echo "Create table..."
$CLIENT --port $PORT --multiquery < table_setup.sql

echo "Import dataset..."
$CLIENT --port $PORT --time --query "INSERT INTO hits FORMAT TSV" < hits.tsv
