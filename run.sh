#!/usr/bin/env bash

max_depth=1
max_fanout=1
min_depth=1
min_fanout=1
range=0
xml_only=0
file_location="graphs/clock_tree_instance_"$depth"_"$fanout".xml"
object_location="objects/clock_tree"
results_file="clock_tree_results.csv"
xmlc_arguments=""
placement=""
threads=""
contraction=""
send_over_recv=""
csv=""

function print_usage()
{
    echo "clock_tree test script"
    echo "run [--range] --depth=d --fanout=f "
    echo ""
    echo "  --help                 : Print this usage information"
    echo ""
    echo "  -c | --csv             : Provide a CSV file, with two columns, depth and fanout, for any number of rows."
    echo "                           All of these depth/fanout pairs will be run"
    echo ""
    echo "  -r | --range           : Boolean - runs from a min depth (default 1) and a min fanout (default 1) to given depth/range"
    echo ""
    echo "  -d | --depth=d         : Integer - The depth (or maximum depth) of the graph(s) to be generated and tested"
    echo ""
    echo "  --min-depth=d          : Integer - The minimum depth for the range of depths to be tested."
    echo ""
    echo "  --min-fanout=f         : Integer - The minimum fanout for the range of fanouts to be tested. "
    echo ""
    echo "  -f | --fanout=f        : Integer - The fanout (or maximum fanout) of the graph(s) to be generated and tested"
    echo ""
    echo "  -x | --xml-only        : Boolean - Only build the XML of the given depth/fanout (including range). Will be stored in /graphs/"
    echo ""
    echo "  --results=r            : Filepath - Location for execution time results to be stored in"
    echo ""
    echo "  -p | --placement=p     : Keyword - cluster      : generate a new clustered placement based on thread count"
    echo "                                     cluster-core : generate a new clustered placement based on cores"
    echo "                                     cluster-mbox : generate a new clustered placement based on mailboxes"
    echo "                                     random       : use a different placement each time (default)"
    echo ""
    echo "  -t | --threads=t       : Integer - Number of active threads to target"
    echo ""
    echo "  --contraction=method   : Keyword - How to place n threads on the h hardware threads"
    echo "                                     dense : map active thread i to hardware thread i"
    echo "                                     sparse : map active threads i to hardware thread floor(i*(h/n))"
    echo "                                     random : select a random subset"
    echo "  --send-over-recv=value : Prefer to send (fill network) rather than recv (drain)"
    echo "                                     0 : receive rather than send (default)"
    echo "                                     1 : send rather than send"
    echo ""
}

function prepare_xmlc_arguments()
{

    xmlc_arguments="--vcode="$object_location"_code.v --vdata="$object_location"_data.v"
    xmlc_arguments="$xmlc_arguments --message-types="$object_location"_messages.csv"
    xmlc_arguments="$xmlc_arguments --app-pins-addr-map="$object_location"_pin_map.csv"
    xmlc_arguments="$xmlc_arguments --measure="$object_location"_"$depth"_"$fanout"_measure.csv -o "$object_location".elf"

    case $placement in

        "cluster") xmlc_arguments="$xmlc_arguments --placement=cluster";;

        "cluster-core") xmlc_arguments="$xmlc_arguments --placement=cluster-core";;

        "cluster-mbox") xmlc_arguments="$xmlc_arguments --placement=cluster-mbox";;

	    "cluster-board") xmlc_arguments="$xmlc_arguments --placement=cluster-board";;

        "random") ;;

        "") ;;

        *) echo "Error - Unrecognised placement method. See --help for details"; exit 1;

    esac

    if [[ "$threads" != "" ]];
    then
        echo "TARGETING $threads THREADS"
        xmlc_arguments="$xmlc_arguments --threads=$threads"
    else
        echo "TARGETING 3072 THREADS"
    fi

    case $contraction in

        "dense") xmlc_arguments="$xmlc_arguments --contraction=dense";;

        "sparse") xmlc_arguments="$xmlc_arguments --contraction=sparse";;

        "random") xmlc_arguments="$xmlc_arguments --contraction=random";;

        "") ;;

        *) echo "Error - Unrecognised placement method. See --help for details"; exit 1;

    esac

    if [[ "$send_over_recv" != "" ]]
    then
        xmlc_arguments="$xmlc_arguments --hardware-send-over-recv=$send_over_recv"
    fi

#    PERFMON? TODO: MAKE THIS AN OPTION
#    xmlc_arguments="$xmlc_arguments --softswitch_enable_profile=1000"
}

function run_test()
{
    depth=$1
    fanout=$2
    complete=0
    file_location="graphs/clock_tree_instance_"$depth"_"$fanout".xml"

    if [ -f $file_location ] ; then
    rm $file_location
    fi


    python create_clock_tree_instance.py $depth $fanout >> $file_location

    if [[ $xml_only == 0 ]] ; then
        run $file_location;
    fi;
}


function run()
{
    filepath=$1
    while [[ $complete == 0 ]] ; do
        prepare_xmlc_arguments
        pts-xmlc $filepath $xmlc_arguments
		timeout 10m pts-serve --code "$object_location"_code.v --data "$object_location"_data.v --keyvaldst "$object_location"_keyvals.csv  --measuredst "$object_location"_measures.csv --perfmondst "$object_location"_"$depth"_"$fanout"_perfmon.csv --elf "$object_location".elf --headless true
        printf "%d,%d,%s\n" $depth $fanout `cat objects/clock_tree_measures.csv` >> $results_file
        if [[ $? == 0 ]]; then
            complete=1;
        else
            complete=0;
        fi;
	rm objects/*
    done
}

function noOfDevices()
{
    dpth=$1;
    fnt=$2;
    total=0;
    i=0;
    while [ $i -le $dpth ] ; do
        if [ $i -ne $dpth ] ;
        then
            tmp=$((fnt**i))
            tmp=$((tmp*2))
            total=$((total+tmp))
        else
            total=$((total+$((fnt**i))))
        fi;

        if [ $total -gt 3072 ] ;
        then
            i=$((dpth+1))
        else
            i=$((i + 1))
        fi;
    done

    if [ $total -le 1024  ] ;
    then
        threads=1024
    elif [ $total -le 2048 ] ;
    then
        threads=2048
    else
        threads=""
    fi;
}

# ./clean Remove objects and graph directories, to not interfere with new tests

# https://stackoverflow.com/a/31443098
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help) print_usage; exit 1;;

    -c) csv="$2"; shift 2;;
    --csv=*) max_depth="${1#*=}"; shift 1;;
    --csv) echo "$1 requires a filepath to a CSV file"; exit 1;;

    -d) max_depth="$2"; shift 2;;
    --depth=*) max_depth="${1#*=}"; shift 1;;
    --depth) echo "$1 requires an integer argument" >&2; exit 1;;

    -f) max_fanout="$2"; shift 2;;
    --fanout=*) max_fanout="${1#*=}"; shift 1;;
    --fanout) echo "$1 requires an integer argument" >&2; exit 1;;

    --min-depth=*) min_depth="${1#*=}"; shift 1;;
    --min-depth) echo "$1 requires an integer argument" >&2; exit 1;;

    --min-fanout=*) min_fanout="${1#*=}"; shift 1;;
    --min-fanout) echo "$1 requires an integer argument" >&2; exit 1;;

    -r) range=1; shift 1;;
    --range) range=1; shift 1;;

    -x) xml_only=1; shift 1;;
    --xml-only) xml_only=1; shift 1;;

    --results=*) results_file="${1#*=}"; shift 1;;
    --results) echo "$1 requires a filepath argument" >&2; exit 1;;

    -p) placement="$2"; shift 2;;
    --placement=*) placement="${1#*=}"; shift 1;;
    --placement) echo "$1 requires an argument" >&2; exit 1;;

    -t) threads="$2"; shift 2;;
    --threads=*) threads="${1#*=}"; shift 1;;
    --threads) echo "$1 requires an argument" >&2; exit 1;;

    --contraction=*) contraction="${1#*=}"; shift 1;;
    --contraction) echo "$1 requires an argument" >&2; exit 1;;

    --send-over-recv=*) send_over_recv="${1#*=}"; shift 1;;
    --send-over-recv) echo "$1 requires an argument" >&2; exit 1;;

    --*) echo "unknown long option: $1" >&2; exit 1;;

    *) if [[ "${input_file}" == "" ]] ; then
        input_file="$1"; shift 1;
       else
        echo "unexpected argument: $1" >&2; exit 1;
       fi;;
  esac

done

mkdir graphs
mkdir objects
rm -rf $results_file

if [[ "$csv" != "" ]];
then
    python create_clock_tree_instance.py $csv
    for file in ./graphs/*.xml; do
        complete=0
        depth=$(echo $file| cut -d'_' -f 6)
        fanout=$(echo $file| cut -d'_' -f 7)
        fanout=${fanout%.*}
        noOfDevices $depth $fanout
        run $file
    done
    exit 0;
fi;

if [[ "$range" == "1"  ]];
then
    for ((d = $min_depth; d <= $max_depth; d++))
    do
        for ((f = $min_fanout; f <= $max_fanout; f++))
        do
            echo "RUNNING CLOCK_TREE_"$d"_"$f""
            noOfDevices $d $f
            run_test $d $f
        done
    done
else
    echo "RUNNING CLOCK_TREE_"$max_depth"_"$max_fanout""
    noOfDevices $max_depth $max_fanout
    run_test $max_depth $max_fanout
fi
