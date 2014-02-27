#!/usr/bin/perl

use LWP::Simple;
use DB_File;

# Gets stock info from:
# http://ichart.finance.yahoo.com/table.csv?s=SPY&a=11&b=1&c=2011&d=01&e=24&f=2012&g=d&ignore=.csv

# global variables
my $yahooUrl = "http://ichart.finance.yahoo.com/table.csv";
# my $windowInterval = 10;

my $window1 = 13;
my $window2 = 34;
my $window3 = 55;
my $priorMonthsToLoad = 4;

my %stockHoldings;
my %daysHeld;
my %stockChart;
my %stockListing;
my %computerStockPicks;
my %computerStockVolume;
my @orderHistory;
my $totalBets = 0;
my $betsWon = 0;
my $betsLost = 0;
my $betsGains = 0.0;
my $betsLosses = 0.0;

# simulate.pl -load testData 1-1-2011 [1-1-2012],  Loads data from Jan 1, 2011 until the current date into a file called 'testData'
# simulate.pl testData outputFile 100000.0 10 [7.95],  Uses the 'testData' file to run a simulation with $100,000 and 10 open positions.  Outputs results to 'outputFile'.

($#ARGV >= 2) || die "Usage: simulate.pl data/Jan2011 tests/Jan2011-100K-10picks.txt 100000.00 10 [7.95]\nLoad Data: simulate.pl -load testData 1-1-2011 [1-1-2012]\n";

my $commandArg = $ARGV[0];
$commandArg = lc($commandArg);

# load stock listings
my @allStocks = `cat allstocks.csv`;

if ($commandArg eq "-load") {
	dbmopen(%stockChart, $ARGV[1], 0644) || die "Unable to open data file.\n";

	# get time values and set parameters
	# for querying yahoo finance		
	my ($bmonth, $bday, $byear) = split('-', $ARGV[2]);
	my $endDate = "";
	if ($#ARGV >= 3) {
		$endDate = $ARGV[3];
	}
	$bmonth--;

	my $emonth = "";
	my $eday = "";
	my $eyear = "";
	if ($endDate eq "") {
		my @timeValues = localtime(time);
		$eday = $timeValues[3];
		$emonth = $timeValues[4];
		$eyear = $timeValues[5];
		$eyear += 1900;
	}
	else {
		my ($monVal, $dayVal, $yearVal) = split('-', $endDate);
		$eday = $dayVal;
		$emonth = $monVal - 1;
		$eyear = $yearVal;
	}
	# store the start and end dates for future use
	$stockChart{'__startDate__'} = $bmonth."-".$bday."-".$byear;
	$stockChart{'__endDate__'} = $emonth."-".$eday."-".$eyear;

	# Load the S&P index for the specified date range
	my $spyUrl = $yahooUrl."?s=SPY&a=".$bmonth."&b=".$bday."&c=".$byear."&d=".$emonth."&e=".$eday."&f=".$eyear."&g=d&ignore=.csv";
	my $spyCSV = "";
	my @spyHistory;
	$spyCSV = get($spyUrl);
	if (defined($spyCSV) && ($spyCSV ne "")) {
		@spyHistory = split(/\n/, $spyCSV);
		if ($#spyHistory < 0) {
			die "Unable to load S\&P index for time period.\n";
		}
	}
	else {
		die "Unable to load S\&P index for time period.\n";
	}

	# Load each stock listing
	print "Loading stock data and histories.\n";
	for (my $i = 1; $i <= $#allStocks; $i++) {
		my @stockInfo = split(/\;/, $allStocks[$i]);
		my $symbol = $stockInfo[1];
		my $desc = $stockInfo[2];
		my $spySize = $#spyHistory;
		if (loadChartData($symbol, $bmonth, $bday, $byear, $emonth, $eday, $eyear, $spySize) == 1) {
			$stockListing{$symbol} = $desc;
			# print "Loaded ".$symbol." - ".$desc."\n";
			show_progress($i / $#allStocks, $symbol);
		}
	}
	print "\n\n";

	# Save our file and exit the program
	dbmclose %stockChart;
	exit(1);
}


#  Running Simulation from loaded file...

# Load the data file and add stock listings
dbmopen(%stockChart, $ARGV[0], 0644) || die "Unable to open data file.\n";
for (my $i = 1; $i <= $#allStocks; $i++) {
	my @stockInfo = split(/\;/, $allStocks[$i]);
	my $symbol = $stockInfo[1];
	my $desc = $stockInfo[2];
	if (defined($stockChart{$symbol})) {
		$stockListing{$symbol} = $desc;
	}
}

# Retrieve the start and end dates
my ($bmonth, $bday, $byear) = split('-', $stockChart{'__startDate__'});
my ($emonth, $eday, $eyear) = split('-', $stockChart{'__endDate__'});

# Load the S&P index for the specified date range
my $spyUrl = $yahooUrl."?s=SPY&a=".$bmonth."&b=".$bday."&c=".$byear."&d=".$emonth."&e=".$eday."&f=".$eyear."&g=d&ignore=.csv";
my $spyCSV = "";
my @spyHistory;
$spyCSV = get($spyUrl);
if (defined($spyCSV) && ($spyCSV ne "")) {
	@spyHistory = split(/\n/, $spyCSV);
	if ($#spyHistory < 0) {
		die "Unable to load S\&P index for time period.\n";
	}
}
else {
	die "Unable to load S\&P index for time period.\n";
}
my $sp_Total = $ARGV[2];
my $accountTotal = $ARGV[2];
my $totalHoldings = $ARGV[3];

my $commissionFee = 0;
if ($#ARGV >= 4) {
	$commissionFee = $ARGV[4];	
}
$bmonth++;
$emonth++;

# Start the simulation
open(OUTFILE, ">".$ARGV[1]) || die "Unable to open output file.\n";
print OUTFILE "Starting portfolio on ".$bmonth."-".$bday."-".$byear." with \$".$accountTotal."\n";
print OUTFILE "Ending portfolio on ".$emonth."-".$eday."-".$eyear."\n";
print OUTFILE "Portfolio will attempt to contain ".$totalHoldings." open positions.\n";
print OUTFILE "A commission fee of \$".$commissionFee." will apply to every trade.\n";

# Cycle through S&P index each day
my $lastDate = "";
my $sp_Qty = 0;
my $sp_Price = 0;
for (my $i = $#spyHistory; $i > 0; $i--) {
	# If this is the 1st day, then buy S&P at the current price for comparison
	my @dailyData = split(',', $spyHistory[$i]);
	$lastDate = $dailyData[0];
	$sp_Price = $dailyData[6];
	if ($i == $#spyHistory) {		
		$sp_Qty = ($sp_Total - (2 * $commissionFee)) / $sp_Price;
		$sp_Qty = int $sp_Qty;
		$sp_Total = $sp_Total - ($sp_Qty * $sp_Price) - (2 * $commissionFee);
	}
	my $portfolioCurrentValue = getPortfolioValue($lastDate);
	my $sp_currentValue = $sp_Total + ($sp_Qty * $sp_Price);

	# Display the current portfolio's value vs. the S&P index for the current day
	print OUTFILE "\n".$lastDate."\t\$".$portfolioCurrentValue."\tS\&P: \$".$sp_currentValue."\n\n";

	# Check for buys and sells today
	checkForBuys($lastDate);
	checkForSells($lastDate);

	# Update the progress bar
	show_progress(($#spyHistory - $i + 1) / $#spyHistory, $lastDate."  \$".$portfolioCurrentValue." S\&P: \$".$sp_currentValue."\t");
}

# Liquidate our portfolio and see our final value, gains, and losses
sellPortfolio($lastDate);
my $totalCommission = $totalBets * 2 * $commissionFee;
my $profit = $betsGains - $betsLosses - $totalCommission;
print OUTFILE "\n\n";
print OUTFILE "Tot. Bets: ".$totalBets.", Won: ".$betsWon.", Lost: ".$betsLost."\n";
print OUTFILE "Gains: \$".$betsGains."\n";
print OUTFILE "Losses: \$".$betsLosses."\n";
print OUTFILE "Fees: \$".$totalCommission."\n";
print OUTFILE "Profit: \$".$profit."\n\n";
print "\n\n";
dbmclose %stockChart;
close(OUTFILE);
exit(1);

sub loadChartData {
	# loads financial data from finance.yahoo.com for the specified symbol and date range
	my ($symbol, $bmonth, $bday, $byear, $emonth, $eday, $eyear, $listSize) = @_;
	my $retVal = 0;	
	my $bmonth = $bmonth - $priorMonthsToLoad;
	if ($bmonth < 0) {
		$byear--;
		$bmonth += 12;
	}
	my $url = $yahooUrl."?s=".$symbol."&a=".$bmonth."&b=1&c=".$byear."&d=".$emonth."&e=".$eday."&f=".$eyear."&g=d&ignore=.csv";
	my $stockDataCSV = "";
	$stockDataCSV = get($url);
	if (defined($stockDataCSV) && ($stockDataCSV ne "")) {
		my @stockHistory = split(/\n/, $stockDataCSV);

		# If this symbol does not have sufficient history then do not load it.
		# i.e., if I run the simulation from 1-1-2011, then the stock must have a history dating back to 8-1-2010,
		# in order to calculate the moving averages.
		if ($#stockHistory >= $listSize + $window3) {
			$stockChart{$symbol} = $stockDataCSV;
			$retVal = 1;
		}
	}
	return ($retVal);
}

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

sub numOfPositions {
	# Returns the number of open positions you currently have
	my @holdings = keys %stockHoldings;
	if ($#holdings == -1) {
		return(0);
	}
	else {
		my $numOfTotalHoldings = $#holdings + 1;
		return ($numOfTotalHoldings);
	}
}

sub isOwnedAlready {
	# Returns true/false depending on whether you currently hold a specified symbol
	# in your portfolio.
	my ($ownedSymbol) = @_;
	if (defined $stockHoldings{$ownedSymbol}) {
		return (1);
	}
	else {
		return (0);
	}
}

sub getPortfolioValue {
	# Returns the value of your portfolio on a given day
	my ($todaysDate) = @_;
	my $retVal = $accountTotal;
	my @holdings = sort keys %stockHoldings;
	for (my $i = 0; $i <= $#holdings; $i++) {
		my $sellPrice = 0;
		my ($qty, $buyPrice) = split(',', $stockHoldings{$holdings[$i]});
		my $stockDataCSV = "";
		$stockDataCSV = $stockChart{$holdings[$i]};
		my @stockHistory = split(/\n/, $stockDataCSV);
		for (my $i = 1; $i <= $#stockHistory; $i++) {
			my @stockData = split(',', $stockHistory[$i]);
			if ($stockData[0] eq $todaysDate) {
				$sellPrice = $stockData[6];
			}
		}
		$retVal = $retVal + ($qty * $sellPrice);
	}
	return ($retVal);
}

sub sellStock {
	# Simulates selling a stock on a given day
	# This simulation assumes you can sell at the last day's closing price. 

	my ($sellSymbol, $sellPrice) = @_;
	my $isOwned = isOwnedAlready ($sellSymbol);
	if ($isOwned == 1) {
		my @buyInfo = split(',', $stockHoldings{$sellSymbol});
		my $buyQty = $buyInfo[0];
		my $buyPrice = $buyInfo[1];
		
		if ($sellPrice > $buyPrice) {
			$betsWon++;
			$betsGains += ($buyQty * ($sellPrice - $buyPrice));
		}
		else {
			$betsLosses += ($buyQty * ($buyPrice - $sellPrice));
			$betsLost++;
		}
		$accountTotal = $accountTotal + ($buyQty * $sellPrice) - $commissionFee;
		print OUTFILE "\tSold ".$buyQty." share(s) of ".$sellSymbol." at \$".$sellPrice.", Balance: \$".$accountTotal."\n";
		delete $stockHoldings{$sellSymbol};
		delete $daysHeld{$sellSymbol};
	}
	return (1);
}

sub buyStock {
	# Simulates buying a stock on a given day
	# This simulation assumes you can buy at the last day's closing price. 

	my ($buySymbol, $quantity, $price) = @_;
	my $isOwned = isOwnedAlready ($buySymbol);
	if ($isOwned == 0) {
		$stockHoldings{$buySymbol} = $quantity.",".$price;
		$daysHeld{$buySymbol} = 0;
		$accountTotal = $accountTotal - ($quantity * $price) - $commissionFee;
		print OUTFILE "\tBought ".$quantity." share(s) of ".$buySymbol." at \$".$price.", Balance.: \$".$accountTotal."\n";
		$totalBets++;
	}
	return (1);
}

sub clearStockPicks {
	# Clear all the stocks the computer has picked
	my @picks = sort keys %computerStockPicks;
	for (my $i = 0; $i <= $#picks; $i++) {
		delete $computerStockPicks{$picks[$i]};
		delete $computerStockVolume{$picks[$i]};
	}
	return(1);
}

sub getTodaysStockPicks {
	# Populate the list of picks for a given day from the computer's criteria
	my ($todaysDate) = @_;	
	print OUTFILE "\tSearching stock market...\n";
	foreach my $symbol (sort keys %stockListing) {
		my $skipSymbol = isOwnedAlready ($symbol);
		
		if ($skipSymbol == 0) {
			my $stockDataCSV = "";
			$stockDataCSV = $stockChart{$symbol};
			my @stockHistory = split(/\n/, $stockDataCSV);
			my $dayIndex = -1;
			for (my $i = 1; $i <= $#stockHistory; $i++) {
				my @stockData = split(',', $stockHistory[$i]);
				if ($stockData[0] eq $todaysDate) {					
					$dayIndex = $i;
				}
			}
			my $stockPrice = 0;
			my $stockClose = 0;
			my $window1Avg = 0;
			my $window3Avg = 0;

			my @tr, @diPos, @diNeg, @tr14, @diPos14, @diNeg14;
			my @dx, @adx, @gain, @loss, @rs, @rsi;
			

			if ($dayIndex >= 0) {
				for (my $dayCount = $dayIndex + $window3 - 1; $dayCount >= $dayIndex; $dayCount--) {			
					my @stockData = split(',', $stockHistory[$dayCount]);	
					my @stockDataPrev = split(',', $stockHistory[$dayCount + 1]);

					my $tr = 0;
					my $range1 = $stockData[2] - $stockData[3];
					my $range2 = $stockData[2] - $stockDataPrev[6];
					my $range3 = $stockData[3] - $stockDataPrev[6];
					
					if ($stockData[6] > $stockDataPrev[6]) {
						$gain[$dayCount - $dayIndex] = $stockData[6] - $stockDataPrev[6];
						$loss[$dayCount - $dayIndex] = 0;
					}
					else {
						$gain[$dayCount - $dayIndex] = 0;
						$loss[$dayCount - $dayIndex] = $stockDataPrev[6] - $stockData[6];
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

					$tr[$dayCount - $dayIndex] = $tr;
					$diPos[$dayCount - $dayIndex] = $diPos;
					$diNeg[$dayCount - $dayIndex] = $diNeg;
					$stockClose = $stockData[6];
					$window3Avg += $stockClose;			
					if ($dayCount == $dayIndex) {
						$stockPrice = $stockClose;
					}										
					if ($dayCount < $dayIndex + $window2) {
						my $tr14 = 0, $diPos14 = 0, $diNeg14 = 0, $avgGain14 = 0, $avgLoss14 = 0, $rs14 = 0, $rsi14 = 100;
						for (my $j = $dayCount - $dayIndex; $j < $dayCount - $dayIndex + ($window3 -$window2); $j++) {
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
						
						$rs[$dayCount - $dayIndex] = $rs14;
						$rsi[$dayCount - $dayIndex] = $rsi14;

						if ($tr14 > 0) {
							$tr14[$dayCount - $dayIndex] = $tr14;
							$diPos14 = 100 * $diPos14 / $tr14;
							$diNeg14 = 100 * $diNeg14 / $tr14;
							$diPos14[$dayCount - $dayIndex] = $diPos14;
							$diNeg14[$dayCount - $dayIndex] = $diNeg14;
							my $posDir = $diPos14 + $diNeg14;
							my $negDir = $diPos14 - $diNeg14;
							if ($negDir < 0) { $negDir *= -1; }
							if ($posDir > 0) {
								$dx[$dayCount - $dayIndex] = 100 * $negDir / $posDir;
							}
							else { $dx [$dayCount - $dayIndex] = 0; }
						}
						else {
							$tr14[$dayCount - $dayIndex] = $tr[$dayCount - $dayIndex + 1];
							$diPos14[$dayCount - $dayIndex] = $diPos14[$dayCount - $dayIndex + 1];
							$diNeg14[$dayCount - $dayIndex] = $diNeg14[$dayCount - $dayIndex + 1];
							$dx[$dayCount - $dayIndex] = $dx[$dayCount - $dayIndex + 1];
						}						

						if ($dayCount < $dayIndex + $window1) {
							my $adx = 0, $rsiAvg = 0, $trAvg = 0, $diPosAvg = 0, $diNegAvg = 0;
							if ($dayCount < $dayIndex + $window1 - 1) {
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
								for (my $j = $dayCount - $dayIndex; $j < $dayCount - $dayIndex + ($window2 - $window1); $j++) {
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
				}
			}
			$window3Avg = $window3Avg / $window3;
			$window1Avg = $window1Avg / $window1;

			# is the MA from Window 3 < MA from Window 1 
			if ( ($window3Avg > 0) && ($window1Avg < $window3Avg) && ($stockPrice < $window1Avg)) {
				if ( ($adx[0] > 30)  && ($adx[0] < 45) && ($adx[($window1 / 2) - 2] < $adx[0])) {
					if (($rsi[0] > 45) && ($rsi[0] < 60) && ($rsi[($window1 / 2) - 2] > $rsi[0])) {
						$computerStockPicks{$symbol} = $stockPrice;
						$computerStockVolume{$symbol} = 100 - $adx[0];
					}
				}
			}
			# found our stock
		} 
	} # loop to next stock
}

sub sellPortfolio {
	my ($todaysDate) = @_;		
	my @holdings = sort keys %stockHoldings;
	for (my $i = 0; $i <= $#holdings; $i++) {
		my $stockDataCSV = "";
		$stockDataCSV = $stockChart{$holdings[$i]};
		my @stockHistory = split(/\n/, $stockDataCSV);
		my $stockPrice = 0;
		if ($#stockHistory >= 1)  {			
			my @stockData = split(',', $stockHistory[1]);			
			my $stockClose = 0;
			$stockPrice = $stockData[6];
			my $sellSymbol = $holdings[$i];
			sellStock($sellSymbol, $stockPrice);						
		}								
	}
	return (1);
}

sub checkForSells {
	my ($todaysDate) = @_;	
	my @holdings = sort keys %stockHoldings;
	for (my $i = 0; $i <= $#holdings; $i++) {
		my $stockDataCSV = "";
		$stockDataCSV = $stockChart{$holdings[$i]};
		my @stockHistory = split(/\n/, $stockDataCSV);
		my $dayIndex = -1;
		for (my $i = 1; $i <= $#stockHistory; $i++) {
			my @stockData = split(',', $stockHistory[$i]);
			if ($stockData[0] eq $todaysDate) {
				$dayIndex = $i;
			}
		}
		
		my $stockPrice = 0;
		my $window1Avg = 0;
		my $window3Avg = 0;

		if ($dayIndex >= 0) {
			for (my $dayCount = $dayIndex; $dayCount < $dayIndex + $window3; $dayCount++) {	
				my @stockData = split(',', $stockHistory[$dayCount]);			
				my $stockClose = 0;
				$stockClose = $stockData[6];
				$window3Avg += $stockClose;
				if ($dayCount == $dayIndex) {
					$stockPrice = $stockClose;
				}							
				if ($dayCount < $dayIndex + $window1) {
					$window1Avg += $stockClose;
				}
			}
			$window3Avg = $window3Avg / $window3;
			$window1Avg = $window1Avg / $window1;

			my $sellSymbol = $holdings[$i];
			my $daysToHold = 3;
			if ($daysHeld{$sellSymbol} > $daysToHold) {
				if (($stockPrice > $window3Avg) || ($window1Avg > $window3Avg)) {
						sellStock($sellSymbol, $stockPrice);
				}
			}
			else {
				$daysHeld{$sellSymbol} = $daysHeld{$sellSymbol} + 1;
			}
		}
							
	}
	return (1);
}

sub checkForBuys {
	my ($todaysDate) = @_;	
	my $numOfHoldings = numOfPositions();
	if ( ($numOfHoldings < $totalHoldings) && ($accountTotal > (2* $commissionFee)) ) {
		clearStockPicks();
		getTodaysStockPicks($todaysDate);
		my @picksSorted = sort keys %computerStockPicks;		
		for (my $i = 0; $i <= $#picksSorted; $i++) {
			for (my $j = $i; $j <= $#picksSorted; $j++) {
				my $vol1 = $computerStockVolume{$picksSorted[$i]};
				my $vol2 = $computerStockVolume{$picksSorted[$j]};

				if ($vol2 > $vol1) {
					my $temp = $picksSorted[$i];
					$picksSorted[$i] = $picksSorted[$j];
					$picksSorted[$j] = $temp;
				}								
			}
		}
		if ($#picksSorted >= 0) {
			my $numOfPicks = $#picksSorted + 1;
			print OUTFILE "\tFound ".$numOfPicks." matching stocks.\n";
			my $stockTradingCap = $accountTotal / ($totalHoldings - $numOfHoldings);
			if ($#picksSorted < ($totalHoldings - $numOfHoldings)) {
				for (my $i = 0; $i <= $#picksSorted; $i++) {
					my $buySymbol = $picksSorted[$i];
					my $buyPrice = $computerStockPicks{$picksSorted[$i]};
					my $buyQty = ($stockTradingCap - (2 * $commissionFee)) / $buyPrice;
					$buyQty = int $buyQty;
					buyStock($buySymbol, $buyQty, $buyPrice);
				}
			}
			else {				 				
				for (my $i = 0; $i < $totalHoldings - $numOfHoldings; $i++) {
					if ($i <= $#picksSorted) {
						my $buySymbol = $picksSorted[$startIndex + $i];
						my $buyPrice = $computerStockPicks{$picksSorted[$startIndex + $i]};
						my $buyQty = ($stockTradingCap - (2 * $commissionFee)) / $buyPrice;
						$buyQty = int $buyQty;
						buyStock($buySymbol, $buyQty, $buyPrice);
					}
				}
			}
		}
		else {
			print OUTFILE "\tNo stocks found to fill open position(s)...\n";
		}	
	} # we have met our number of holdings now, exit.
	return (1);
}


