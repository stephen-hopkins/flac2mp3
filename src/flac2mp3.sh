#!/bin/bash
inputDir=$1
outputDir=$2
topDir=$(pwd)
cd "$inputDir"
for d1 in *; do
	echo "d1: $d1"
	for d2 in "$d1"/*; do
		(
		echo "d2: $d2"
		cd "$d2"
		parallel ffmpeg -i {} -vsync 0 -qscale:a 0 {.}.mp3 ::: *.flac
		mkdir -p "$topDir/$outputDir/$d2"
		if ls *.flac> /dev/null 2>&1; then
			mv *.mp3 "$topDir/$outputDir/$d2"
		else
			cp *.mp3 "$topDir/$outputDir/$d2"
		fi
		)
	done
done
