[ -e axitrack.txt ] && rm axitrack.txt

DIR="$(dirname "${BASH_SOURCE[0]}")" 
DIR="$(realpath "${DIR}")"  
SCRIPTPATH=$DIR

#mkdir -p $SCRIPTPATH/../pickle
mkdir -p $SCRIPTPATH/pickle

python3 osnt-tool-cmd.py -new
#python3 osnt-tool-cmd.py -ifp0 ../sample_traces/256.cap -rpn0 100 -ipg0 0 #-rxs0 26 -txs0 16
python3 osnt-tool-cmd.py -ifp1 ../sample_traces/256.cap -rpn1 2 -ipg1 0
#-rxs1 26 -txs1 16
#python osnt-tool-cmd.py -ifp2 ../sample_traces/512.cap -rpn2 100 -ipg2 0 -rxs2 32 -txs2 64
#python osnt-tool-cmd.py -ifp3 ../sample_traces/512.cap -rpn3 200 -ipg3 0 -rxs3 32 -txs3 64
python3 osnt-tool-cmd.py -run


