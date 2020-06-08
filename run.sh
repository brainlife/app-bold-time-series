#!/bin/bash

set -e
set -x

# if py_bin not exported to script, use "python3"
if [[ -z ${py_bin} ]] ; then
	py_bin=python3
fi

EXEDIR=$(dirname "$(readlink -f "$0")")/

###############################################################################

# where to output stuff
inOUTBASE=${PWD}/

# read inputs from jq

# required
inFMRI=`jq -r '.fmri' config.json`
inPARC=`jq -r '.parc' config.json`
inCONF=`jq -r '.confounds' config.json`
inMASK=`jq -r '.mask' config.json`

# made by fmriprep
inCONFJSON=`jq -r '.confjson' config.json`

# OPTS for regression
inSMOOTH=`jq -r '.smoothfwhm' config.json`
# need TR for smoothing
inTR=`jq -r '.tr' config.json`
inLOWPASS=`jq -r '.lowpass' config.json`
inHIGHPASS=`jq -r '.highpass' config.json`

# OPTS for make TS
# control resolution 
inSPACE=`jq -r '.inspace' config.json`

# important regression strategy to choose!! 
inSTRATEGY=`jq -r '.strategy' config.json`

################################################################################

# check the main stuff we need
if [[ ${inFMRI} = "null" ]] ||
	[[ ${inPARC} = "null" ]] ||
	[[ ${inCONF} = "null" ]] ||
	[[ ${inMASK} = "null" ]] ; then
	echo "ERROR: need an fmri, parc, mask, and confounds file at minimum" >&2;
	exit 1
fi

# set the default to data space
if [[ ${inSPACE} = "null" ]] ; then
	inSPACE="data"
fi

###############################################################################
# try to get repeition time if not provided

if [[ ${inTR} = "null" ]] ; then

	blJson=$(dirname ${inFMRI})/.brainlife.json

	if [[ -f ${blJson} ]] ; then
		getTr=$(jq -r '.meta.RepetitionTime' ${blJson})
		if [[ ${getTr} != "null" ]] ; then
			inTR=${getTr}
		fi
	else
		echo "blJson not found, not reading TR from here"
	fi
fi

# make sure inTR is not ''
if [[ -z ${inTR} ]] ; then
	echo "DETECTED that 'inTR' was ''... will try to guess TR... \
		  this might cause problems... so Im telling you. \
		  Please provide TR for no problems!!!"
	inTR="null"
fi

###############################################################################
# run it

mkdir -p ${inOUTBASE}/output_regress/

cmd="${py_bin} ${EXEDIR}/src/regress.py \
		-out ${inOUTBASE}/output_regress/out \
		${inFMRI} \
		${inCONF} \
		-mask ${inMASK} \
		-discardvols 0 \
	"
if [[ ${inCONFJSON} != "null" ]] ; then
  cmd="${cmd} -confjson ${inCONFJSON}"
fi
if [[ ${inSMOOTH} != "null" ]] ; then
  cmd="${cmd} -fwhm ${inSMOOTH}"
fi
if [[ ${inTR} != "null" ]] ; then
	cmd="${cmd} -tr ${inTR}"
fi
if [[ ${inLOWPASS} != "null" ]] ; then
  cmd="${cmd} -lowpass ${inLOWPASS}"
fi
if [[ ${inHIGHPASS} != "null" ]] ; then
  cmd="${cmd} -highpass ${inHIGHPASS}"
fi
if [[ ${inSTRATEGY} != "null" ]] ; then
  cmd="${cmd} -strategy ${inSTRATEGY}"
fi
echo $cmd
eval $cmd

regressFMRI=${inOUTBASE}/output_regress/out_nuisance.nii.gz
if [[ ! -f ${regressFMRI} ]] ; then
	echo "ERROR: something wrong with nusiance regression" >&2; 
	exit 1
else
	# rename
	mv ${regressFMRI} ${inOUTBASE}/output_regress/bold.nii.gz 
fi

################################################################################
# make time series

mkdir -p ${inOUTBASE}/output_ts/

cmd="${py_bin} ${EXEDIR}/src/makemat.py \
	-savetimeseries -nomatrix \
    -space ${inSPACE} \
    -out ${inOUTBASE}/output_ts/out \
    ${inOUTBASE}/output_regress/bold.nii.gz \
    ${inMASK} \
    -parcs ${inPARC} \
  "
echo $cmd
eval $cmd

outTS=$(ls ${inOUTBASE}/output_ts/out_*_timeseries.hdf5)
if [[ ! -f ${outTS} ]] ; then
	echo "ERROR: something wrong with making TS" >&2; 
	exit 1
else
	# rename
	mv ${outTS} ${inOUTBASE}/output_ts/timeseries.hdf5
	# and copy over the key and label.json for future matrix making
	cp `jq -r '.key' config.json` ${inOUTBASE}/output_ts/key.txt
	cp `jq -r '.label' config.json` ${inOUTBASE}/output_ts/label.json
fi

# end run.sh
