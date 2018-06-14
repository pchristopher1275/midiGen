#!/usr/bin/perl
#!/Users/pete/perl5/perlbrew/perls/perl-5.16.0/bin/perl
use strict;
use Data::Dumper;

##http://en.wikibooks.org/wiki/Music_Theory/Complete_List_of_Chord_Patterns

# scales.
# All scales contain 7 notes. Each scale contains 12 chromatic notes. That is, we don't 
# include the octave in either the chromatic nor the full scale.
#                  1     2     3  4     5     6     7
my @gMajorScale = (1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1);

my @gModes = qw(
   Ionian 
   Dorian
   Phrygian
   Lydian
   Mixolydian
   Aeolian
   Locrian
);

my %gModeOffsets = map {$gModes[$_] => $_} 0 .. $#gModes;

my @gChords = (
    {name=>"maj", index=>[qw/1 3 5/], mode=>"ionian", fullname=>"major scale"},
    {name=>"maj7", index=>[qw/1 3 5 7/], mode=>"ionian", fullname=>"major seventh"},
    {name=>"majadd6", index=>[qw/1 3 5 6/], mode=>"ionian", fullname=>"major sixth"},

    {name=>"min", index=>[qw/1 b3 5/], mode=>"dorian,aeolian", fullname=>"minor scale"},
    {name=>"min7", index=>[qw/1 b3 5 b7/], mode=>"dorian,aeolian", fullname=>"minor seventh"},
    {name=>"minadd6", index=>[qw/1 b3 5 6/], mode=>"dorian", fullname=>"minor sixth"},

    {name=>"dom", index=>[qw/1 3 5 b7/], mode=>"dorian,aeolian", fullname=>"dominant seventh"},    
    {name=>"sus4", index=>[qw/1 4 5/], mode=>"mixolydian", fullname=>"suspended fourth"},
    {name=>"sus2", index=>[qw/1 2 5/], mode=>"mixolydian", fullname=>"suspended second"},

    {name=>"dim", index=>[qw/1 b3 b5 /], mode=>"", fullname=>"diminished"},

);




sub isScale {
    my ($a) = @_;
    return 0 if (ref($a) ne 'ARRAY');

    my $chromeCount = (grep {$_ == 1 || $_ == 0} @$a);
    my $scaleCount = (grep {$_ == 1} @$a);
    my $allCount = @$a;

    if ($allCount == $chromeCount && $chromeCount % 12 == 0 && $scaleCount % 7 == 0) {
        return 1;
    } else {
        return 0;
    }
}

sub scale2string {
    my ($scale) = @_;
    die "scale2string passed non-scale" unless isScale($scale);
    return join(",", @$scale);
}

sub shiftScale {
    my ($scale, $shift) = @_;
    die "shiftScale passed nonscale" unless isScale($scale);
    die "Bad shift value $shift" if ($shift < 0 || $shift > 7);
    if ($shift == 0){
       return [@$scale];
    }
    my @beg = @$scale;
    my @end;    
    my $nnotes = @$scale;
    my $count = -1;
    for my $i (0 .. ($nnotes-1)) {
        if ($beg[0] == 1) {
            $count++;
            goto END if $count == $shift;                        
        }
        push @end, shift(@beg);
    }
    die "Failed to find shift $shift in scale " . scale2string($scale);
  END:
    push @beg, @end;

    return \@beg;
 }

sub extendScale {
    my ($scale, $oct) = @_;
    die "extendScale called with non-scale" unless isScale($scale);
    die "extendScale called with bad octaves argument" unless $oct =~ /^\d+$/;
    my @new;
    for (1 .. $oct) {
        push @new, @$scale;
    }
    return \@new;
}

sub isChord {
   my ($a) = @_;
   return (grep {$_ == 1 || $_ == 0} @$a) == @$a && @$a == 12;
}

sub chordFromIndexs {
    my ($indexs) = @_;
    die "Poorly formatted indexs passed to chordFromIndexs" 
        unless ref($indexs) eq 'ARRAY' && 
               (grep {/^[b#]?\d+$/} @$indexs) == @$indexs;

    my %indexMap;
    my $pos = 1;
    for my $i (0 .. $#gMajorScale) {
        if ($gMajorScale[$i] == 1) {
            $indexMap{$pos} = $i;
            $pos++;
        }
    }

    my @chord = map {0} @gMajorScale;
    for my $index (@$indexs) {
        my ($bs, $num) = ($index =~ /([b#])?(\d+)/);
        die "INTERNAL ERROR" unless defined($num);
        my $chordPos = $indexMap{$num};
        if (!defined $bs) {
            $chord[$chordPos] = 1;
        } elsif ($bs eq 'b') {
            $chord[$chordPos-1] = 1;
        } else { # sharp #
            $chord[$chordPos+1] = 1;
        }
    }
    return \@chord;
}
sub chord2grid {
   my ($chord) = @_;
   die "bad arg to chord2grid" unless isChord($chord);
   my @grid = (map {[$_]} @$chord);
   return \@grid;
}

sub dumpGrid {
    my ($g) = @_;
    for my $row (@$g) {
        print join(",", @$row), "\n";
    }
}

sub scale2grid {
    my ($scale) = @_;
    die "scale2grid passed a non-scale" unless isScale($scale);
    my @scale = @$scale;    
    my $nrows = @scale;
    my $ncols = (grep {$_ == 1} @scale);

    my @grid = ();

    for my $row (1 .. $nrows) {
        for my $col (1 .. $ncols) {
            $grid[$row-1][$col-1] = '.'
        }
    }

    my $scaleCount = 1;
    for my $col (1 .. $ncols) {
        for my $row (1 .. $nrows) {
            if ($scale[$row-1] == 1) {
                $grid[$row-1][$col-1] = $scaleCount++;
                $scale[$row-1] = 0;
                last;
            }
        }
    }
    
    return \@grid;
}

sub grid2string {
    my ($g) = @_;
    my $nrows = @$g;
    my $ncols = @{$g->[0]};
    my $field = "%3s";
    my $buffer = "";

    $buffer .= sprintf($field, "");
    for my $col (1 .. $ncols) {
        $buffer .= sprintf($field, $col);
    }
    $buffer .= "\n";

    $buffer .= sprintf($field, "");
    for my $col (1 .. $ncols) {
        $buffer .= sprintf($field, "_");
    }
    $buffer .= "\n";

    for my $row (reverse 1 .. $nrows){
        $buffer .= sprintf($field, $row . ":");
        for my $col (1 .. $ncols) {
            $buffer .= sprintf($field, $g->[$row-1][$col-1])
        }
        $buffer .= "\n"
    }

    return $buffer;
}

sub scale2gridstring {
    my ($scale) = @_;
    die "scale2gridstring passed a non-scale" unless isScale($scale);
    my $g = scale2grid($scale);
    return grid2string($g)
}



##
## Guitar Graph 
##
sub isGuitarGraph {
    my ($guitarGraph) = @_;
    return 0 unless ref($guitarGraph) eq 'HASH';
    return 0 unless defined $guitarGraph->{graph};
    my $graph = $guitarGraph->{graph};
    return 0 unless ref($graph) eq 'ARRAY' && @$graph > 0;
    for my $row (@$graph) {
        return 0 unless ref($row) eq 'ARRAY';
        for my $e (@$row) {
            return 0 unless ($e == 0 || $e == 1 || $e == 2)
        }
    }
    return 1;
}

sub equivScaleIndex {
    my ($index, $scale) = @_;
    die "equivScaleIndex bad index ($index)" unless ($index =~ /^-?\d+$/);
    die "equivScaleIndex bad scale" unless isScale($scale);
    my $scaleLength = @$scale;    
    if ($index >= 0) {
            $index = $index % $scaleLength;
    } else {
        for (my $N=1; $N < 10; $N++){
            if ($index + $N*$scaleLength > 0) {
                $index = $index + $N*$scaleLength;
                last;
            }
        }
        die "INTERNAL EROR" if $index < 0;
    }
    return $index;
}

sub generateGuitarGraph {
    my ($scale, $numstrings, $upstring, $downstring) = @_;
    die "Passed a non-scale to generateGuitarGraph" unless isScale($scale);
    my $scaleLength = @$scale;    
    die "Bad numstrings $numstrings" unless defined($numstrings) && $numstrings > 0;
    die "Bad upstring $upstring" unless defined($upstring) && $upstring > 0 && $upstring <= $scaleLength;
    die "Bad downstring $downstring" unless defined($downstring) && $downstring > 0 && $upstring <= $scaleLength;

    my $wrapScale = sub {
        my ($index) = @_;
        $index = equivScaleIndex($index, $scale);
        return 2 if $index == 0;
        return $scale->[$index];
    };


    # ## init graph
    my @graph = map {[map {0} 1 .. ($upstring+$downstring)]} 1 .. $numstrings;

    ## Set guitar graph
    my $graphRoot = $downstring;
    for (my $whichString = 0; $whichString < $numstrings; $whichString++) {        
        my $offset = ($numstrings-$whichString-1)*5;
        for (my $i = -$downstring; $i <= $upstring; $i++) {
            $graph[$whichString][$graphRoot+$i] = $wrapScale->($i+$offset); 
        }
    }

    return {graph => \@graph, root=>$graphRoot};
}
 
sub renderGuitarGraph {
    my ($guitarGraph) = @_;
    die "renderGuitarGraph passed non-GuitarGraph" unless isGuitarGraph($guitarGraph);
    my ($graph, $root) = @{$guitarGraph}{qw/graph root/};
    my $buffer = "";
    for (my $whichString = 0; $whichString < @$graph; $whichString++) { 
        my $row = $graph->[$whichString];
        my @render = map {$_ == 2 ? "O" : $_ == 1 ? "o" : "-"} @$row;      
        $buffer .= "---";  
        $buffer .= join('', @render);
        $buffer .= "---";          
        $buffer .= "\n";
    }
    return $buffer;
}

sub chordFits {
    my ($scale, $chords, $chordNames) = @_;
    die "chordFits passed non scale" unless isScale($scale);
    my $bdArg = sub {die "chordFits passed bad chords arg";};
    $bdArg->() unless ref($chords) eq 'ARRAY';
    for my $c (@$chords) {
        $bdArg->() unless isChord($c);
    }
    die "chordFits passed bad chordNames arg" unless ref($chordNames) eq 'ARRAY' && @$chordNames == @$chords;

    my $scaleCount = 0;
    for my $scaleIndex (0 .. $#$scale) {
        next unless $scale->[$scaleIndex] == 1;
        print "   note ", $scaleCount+1, ": ";        
        for my $chordIndex (0 .. $#$chords) {
            my $chord = $chords->[$chordIndex];
            my $name = $chordNames->[$chordIndex];
            my $chordMatches = 1;
            for my $i (0 .. $#$chord) {
                next unless $chord->[$i] == 1;
                my $matchIndex = $i + $scaleIndex;
                my $eqIndex = equivScaleIndex($matchIndex, $scale);
                if ($scale->[$eqIndex] != 1) {
                    $chordMatches = 0;
                    last;
                }
            }
            if ($chordMatches) {
                print "$name ";
            }    
        }
        print "\n";
        $scaleCount++;
    }

}


sub divider {
   print "=" x 100, "\n";
}


sub main {

    my (@allChords, @allChordNames);
    for my $chord (@gChords) {
       my $index = $chord->{index};
       my $vect = chordFromIndexs($index);
       my $grid = chord2grid($vect);
       my $out = grid2string($grid);
       divider();
       print "Name $chord->{name}\n";
       print "$out\n";
       push @allChords, $vect;
       push @allChordNames, $chord->{name};
    }

    my $chordNum = 1;
    for my $mode (@gModes){
        my $scale = shiftScale(\@gMajorScale, $gModeOffsets{$mode});
        my $out = scale2gridstring($scale);
        divider();
        print "$mode ($chordNum)\n";
        print "$out\n\n";        
        my $guitarGraph = generateGuitarGraph($scale, 4, 3, 2);
        print "Guitar Graph:\n";
        print renderGuitarGraph($guitarGraph),"\n";   
        print "Safe Chords:\n";
        chordFits($scale, \@allChords, \@allChordNames);
        $chordNum++;
    }

 
}

main();