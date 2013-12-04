#!/bin/sh
./fetch.rb
./elect.rb candidates.csv elect.csv
./format.rb elect.csv | tee formatted.txt
