#!/usr/bin/perl

use LWP::Simple;

# Gets stock info from:
# http://ichart.finance.yahoo.com/table.csv?s=SPY&a=11&b=1&c=2011&d=01&e=24&f=2012&g=d&ignore=.csv

# global variables
my $yahooUrl = "http://ichart.finance.yahoo.com/table.csv";
# my $windowInterval = 10;

my $window1 = 13;
my $window2 = 34;
my $window3 = 55;
my $priorMonthsToLoad = 4;
my %computerStockPicks;
my $firstArgIsDate = 0;

# load stock listings
my @allStocks = `cat allstocks.csv`;
my %stockListing;
for (my $i = 1; $i <= $#allStocks; $i++) {
	my @stockInfo = split(/\;/, $allStocks[$i]);
	$stockListing{$stockInfo[1]} = $stockInfo[2];
}

# get time values and set parameters
# for querying yahoo finance
my @timeValues = localtime(time);
my $emonth = "";
my $eday = "";
my $eyear = "";
if (($#ARGV >= 0) && ($ARGV[0] =~ /\d+\-\d+\-\d+/)) {
	print "Using date: ".$ARGV[0]."\n\n";
	($emonth, $eday, $eyear) = split('-', $ARGV[0]);
	$emonth--;
	$firstArgIsDate = 1;
}
else {	
	$eday = $timeValues[3];
	$emonth = $timeValues[4];
	$eyear = $timeValues[5];
	$eyear += 1900;
}

my $byear = $eyear;
my $bmonth = $emonth - $priorMonthsToLoad;
if ($bmonth < 0) {
	$byear--;
	$bmonth += 12;
}

# get price, min, max history on each stock from yahoo finance
my $symbol = "";
my $symbolsScanned = 0;
my @stockListArray = sort keys %stockListing;
foreach my $symbol (sort keys %stockListing) {		
	my $skipSymbol = 1;
	my $matchSymbol = 0;
	if ( ($#ARGV < 0) || (($#ARGV == 0) && ($firstArgIsDate == 1)) ) {
		$skipSymbol = 0;
		show_progress(++$symbolsScanned / $#stockListArray, "Scanning ".$symbol);
	}
	else {		
		for (my $i = $firstArgIsDate; $i <= $#ARGV; $i++) {
			if ($symbol eq uc $ARGV[$i]) {
				$skipSymbol = 0;
				$matchSymbol = 1;
			}
		}
	}
	if ( $skipSymbol == 0 ) {
		my $url = $yahooUrl."?s=".$symbol."&a=".$bmonth."&b=1&c=".$byear."&d=".$emonth."&e=".$eday."&f=".$eyear."&g=d&ignore=.csv";
		my $stockDataCSV = "";
		$stockDataCSV = get($url);

		if (defined($stockDataCSV) && ($stockDataCSV ne "")) {
			my @stockHistory = split(/\n/, $stockDataCSV);
			my $stockPrice = 0;
			my $stockClose = 0;
			my $window1Avg = 0;
			my $window3Avg = 0;

			my @tr, @diPos, @diNeg, @tr14, @diPos14, @diNeg14;
			my @dx, @adx, @gain, @loss, @rs, @rsi;
			my $dayCount = $window3;

			while (($#stockHistory >= $window3) && ($dayCount > 0)) {			
				my @stockData = split(',', $stockHistory[$dayCount]);	
				my @stockDataPrev = split(',', $stockHistory[$dayCount + 1]);

				my $tr = 0;
				my $range1 = $stockData[2] - $stockData[3];
				my $range2 = $stockData[2] - $stockDataPrev[6];
				my $range3 = $stockData[3] - $stockDataPrev[6];
				
				if ($stockData[6] > $stockDataPrev[6]) {
					$gain[$dayCount] = $stockData[6] - $stockDataPrev[6];
					$loss[$dayCount] = 0;
				}
				else {
					$gain[$dayCount] = 0;
					$loss[$dayCount] = $stockDataPrev[6] - $stockData[6];
				}

				if ($range1 < 0) { $range1 *= -1; }
				if ($range2 < 0) { $range2 *= -1; }
				if ($range3 < 0) { $range3 *= -1; }
				$tr = $range1;
				if ($range2 > $range1) { $tr = $range2; }
				if ($range3 > $range2) { $tr = $range3; }

				my $diPos = $stockData[2] - $stockDataPrev[3];
				my $diNeg = $stockDataPrev[3] - $stockData[3];
				if ($diPos > $diNeg) {
					if ($diPos < 0) { $diPos = 0; }
					$diNeg = 0;
				}
				else {
					if ($diNeg < 0) { $diNeg = 0; }
					$diPos = 0;
				}

				$tr[$dayCount] = $tr;
				$diPos[$dayCount] = $diPos;
				$diNeg[$dayCount] = $diNeg;
				$stockClose = $stockData[6];
				$window3Avg += $stockClose;			
				if ($dayCount == 1) {
					$stockPrice = $stockClose;
				}										
				if ($dayCount <= $window2) {
					my $tr14 = 0, $diPos14 = 0, $diNeg14 = 0, $avgGain14 = 0, $avgLoss14 = 0, $rs14 = 0, $rsi14 = 100;
					for (my $j = $dayCount; $j < $dayCount + ($window3 - $window2); $j++) {
						$tr14 += $tr[$j];
						$diPos14 += $diPos[$j];
						$diNeg14 += $diNeg[$j];
						$avgGain14 += $gain[$j];
						$avgLoss14 += $loss[$j];
					}
					$avgGain14 /= ($window3 - $window2);
					$avgLoss14 /= ($window3 - $window2);

					if ($avgLoss14 > 0) {
						$rs14 = $avgGain14 / $avgLoss14;
						$rsi14 = 100 - (100 / (1 + $rs14)); 
					}
					
					$rs[$dayCount] = $rs14;
					$rsi[$dayCount] = $rsi14;

					if ($tr14 > 0) {
						$tr14[$dayCount] = $tr14;
						$diPos14 = 100 * $diPos14 / $tr14;
						$diNeg14 = 100 * $diNeg14 / $tr14;
						$diPos14[$dayCount] = $diPos14;
						$diNeg14[$dayCount] = $diNeg14;
						my $posDir = $diPos14 + $diNeg14;
						my $negDir = $diPos14 - $diNeg14;
						if ($negDir < 0) { $negDir *= -1; }
						if ($posDir > 0) {
							$dx[$dayCount] = 100 * $negDir / $posDir;
						}
						else { $dx [$dayCount] = 0; }
					}
					else {
						$tr14[$dayCount] = $tr14[$dayCount + 1];
						$diPos14[$dayCount] = $diPos14[$dayCount + 1];
						$diNeg14[$dayCount] = $diNeg14[$dayCount + 1];
						$dx[$dayCount] = $dx[$dayCount + 1];
					}						

					if ($dayCount <= $window1) {
						my $adx = 0, $rsiAvg = 0, $trAvg = 0, $diPosAvg = 0, $diNegAvg = 0;
						if ($dayCount < $window1) {
							$adx = $adx[$dayCount - $dayIndex + 1];
							$rsiAvg = $rsi[$dayCount - $dayIndex + 1];
							$trAvg = $tr14[$dayCount - $dayIndex + 1];
							$diPosAvg = $diPos14[$dayCount - $dayIndex + 1];
							$diNegAvg = $diNeg14[$dayCount - $dayIndex + 1];
							$adx[$dayCount - $dayIndex] = (($adx * $window1) + $dx[$dayCount - $dayIndex]) / ($window1 + 1);
							$rsi[$dayCount - $dayIndex] = (($rsiAvg * $window1) + $rsi[$dayCount - $dayIndex]) / ($window1 + 1);
							$tr14[$dayCount - $dayIndex] = (($trAvg * $window1) + $tr[$dayCount - $dayIndex]) / ($window1 + 1);
							$diPos14[$dayCount - $dayIndex] = (($diPosAvg * $window1) + $diPos14[$dayCount - $dayIndex]) / ($window1 + 1);
							$diNeg14[$dayCount - $dayIndex] = (($diNegAvg * $window1) + $diNeg14[$dayCount - $dayIndex]) / ($window1 + 1);
						}
						else {								
							for (my $j = $dayCount; $j < $dayCount + ($window2 - $window1); $j++) {
								$adx += $dx[$j];
								$rsiAvg += $rsi[$j];
								$trAvg += $tr14[$j];
								$diPosAvg += $diPos14[$j];
								$diNegAvg += $diNeg14[$j];
							}
							$adx /= ($window2 - $window1);
							$rsiAvg /= ($window2 - $window1);
							$trAvg /= ($window2 - $window1);
							$diPosAvg /= ($window2 - $window1);
							$diNegAvg /= ($window2 - $window1);							
							$adx[$dayCount - $dayIndex] = $adx;
							$rsi[$dayCount - $dayIndex] = $rsiAvg;
							$tr14[$dayCount - $dayIndex] = $trAvg;
							$diPos14[$dayCount - $dayIndex] = $diPosAvg;
							$diNeg14[$dayCount - $dayIndex] = $diNegAvg;
						}
						$window1Avg += $stockClose;
					}
				}
				$dayCount--;
			}
			$window3Avg = $window3Avg / $window3;
			$window1Avg = $window1Avg / $window1;
		
			if (($#ARGV >= 0) && ($matchSymbol == 1)) {
				print $symbol."\t".$stockListing{$symbol}."\t".$stockPrice."\t".$stockVolume."\n";
				print $window1." day MA: ". $window1Avg."\n";
				print $window3." day MA: ". $window3Avg."\n";
				print $window1." day ADX: ". $adx[1]."\n";
				print $window1." day RSI: ". $rsi[1]."\n\n";

				#for (my $j = $window2; $j >=1; $j--) {
				#	print $j." ".$dx[$j]." ".$adx[$j]." ".$rsi[$j]."\n";
				#}
			}

			else {
				# is the MA from Window 3 < MA from Window 1 
				if ( ($window3Avg > 0) && ($window1Avg < $window3Avg) && ($stockPrice < $window1Avg)) {
					if ( ($adx[1] > 30)  && ($adx[1] < 45) && ($adx[($window1 / 2) - 1] < $adx[1])) {
						if (($rsi[1] > 45) && ($rsi[1] < 60) && ($rsi[($window1 / 2) - 1] > $rsi[1])) {
							$computerStockPicks{$symbol} = $stockPrice."\t".$adx[1];
						}
					}
				}				
			}
		}
	}
}
print "\n\n";
foreach my $computerPick (sort keys %computerStockPicks) {
	print $computerPick."\t".$stockListing{$computerPick}."\t".$computerStockPicks{$computerPick}."\n";
}
exit(1);


sub flush {
   # Flush the stdout buffer
   my $h = select($_[0]); my $a=$|; $|=1; $|=$a; select($h);
}

sub show_progress {
   # Updates the progress bar on stdout
   my ($progress, $symbol, $desc) = @_;
   my $stars   = '=' x int($progress*20);
   my $percent = int($progress*100);
   $percent = $percent >= 100 ? 'done.' : $percent.'%';
   print("\r|$stars\> ($percent) $symbol  ");
   flush(STDOUT);
}

