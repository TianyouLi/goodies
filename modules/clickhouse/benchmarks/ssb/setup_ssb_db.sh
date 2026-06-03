SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/../../helper.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

DBGEN=$SCRIPT_DIR/dbgen
CLIENT=clickhouse-client

ssb_dbgen() {
	scale=$1
	echo "dbgen scale: $scale ... "
	$DBGEN -s $scale -T c
	$DBGEN -s $scale -T l
	$DBGEN -s $scale -T p
	$DBGEN -s $scale -T s
	$DBGEN -s $scale -T d
}

cd $SCRIPT_DIR

if [ $1 ]; then
	PORT=$1
else
	PORT=9000
fi

if [ ! -f "date.tbl" ]; then
	ssb_dbgen 100
fi

echo "Create table..."
$CLIENT --port $PORT --multiquery < table_setup.sql

echo "Import database..."
$CLIENT --port $PORT --query "INSERT INTO customer FORMAT CSV" < customer.tbl
$CLIENT --port $PORT --query "INSERT INTO part FORMAT CSV" < part.tbl
$CLIENT --port $PORT --query "INSERT INTO supplier FORMAT CSV" < supplier.tbl
$CLIENT --port $PORT --query "INSERT INTO lineorder FORMAT CSV" < lineorder.tbl

echo "convert to flat schema..."
$CLIENT --port $PORT --multiquery < flat_schema_convert.sql
