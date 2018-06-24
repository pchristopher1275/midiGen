#!/usr/bin/perl
use strict;
use Data::Dumper;
use Carp;
use File::Temp;
use YAML;

##
## D O C U M E N T A T I O N
##

## Synopsis:
##      midiGen <command> [command-args ...]
## Prelim:
##      When you define a 'Note' use formats like
##          D2
##          Ds-2   which is the same as C#2
##          Db5
## Commands:
##      ## Create a range of in-key notes
##      noteRange <Key-Note> <Tonic-Note> [Velocity:90] [numberOfFrames:1] [Duration:4*960]
##      renameFreeze
## Examples:
##      noteRange G3 F
## P R O C E S S   R U N N I N G
##
my $gVerbose = 1;
sub backtick {
    my ($command, %opts) = @_;
    print "$command\n" if $gVerbose;
    my @lines = `$command`;
    if ($?) {
        confess "Failed '$command': $!" unless $opts{noexit};
        return ();
    }
    chomp(@lines);
    return @lines;
}

sub run {
    my ($cmd) = @_;
    print "$cmd\n" if $gVerbose;
    if (system $cmd){
        confess "Failed: '$cmd': $!";
    }
}

## 
## K E Y
##
my @gMajorScale = (2, 2, 1, 2, 2, 2, 1);
my @gNoteSymbols = qw/ C   C#  D  D#  E   F   F#  G  G#  A A# B  /;
my $gMidiCsvPath = "/Users/pete/midiGen/midicsv-1.1/midicsv";
my $gSoxPath     = "/Users/pete/midiGen/sox-14.4.2/sox";
my $gFlagPitch   = 0;

## Parses notes of the form
##    C2
##    Cs2   which is the same as C#2
##    Cb2
## also accepts integers (as strings) between 0 <= integer < 128
##
sub text2Note {
    my ($text) = @_;
    if ($text =~ /^\d+$/){
        confess "INTERNAL ERROR [1]: bad note" unless $text >= 0 && $text < 128;    
        return $text;
    }

    die "text2Note got a bunk note: '$text'" unless $text =~ /([^\d]+)([-+]?\d)/;

    my $l = uc($1);
    $l =~ s/S/#/; ## We accept s for # -- so it's nicer to work with on command line
    (my $n = $2) =~ s/^\+//;
    my $offset = -1;
    for (my $i = 0; $i < @gNoteSymbols; $i++){
        if ($gNoteSymbols[$i] eq $l){
            $offset = $i;
            last;
        }
    }
    confess "Unable to find letter part of note text '$text'" unless $offset >= 0;
    my $note = ($n+2)*12 + $offset;
    confess "INTERNAL ERROR [2]: bad note" unless $note >= 0 && $note < 128;

    return $note;
}

sub note2Text {
    my ($note) = @_;
    my $noteLetter = $gNoteSymbols[$note % 12];
    my $noteOctave = int($note / 12) - 2;
    $noteLetter =~ s/\#/s/;
    return "${noteLetter}$noteOctave";
}

sub incrementNoteBasedOnScaleDegree {
    my ($note, $scaleDegree) = @_;
    my $index = ($scaleDegree-1) % @gMajorScale;
    return $note + $gMajorScale[$index];
}

## NOTE: scaleDegree is always an integer x with 1 <= x < 8, and is always relative to some key.

## keyOffset is the scale degree that the tonic note is, relative to the key defined by keyNote. 
sub tonicScaleDegreeFromKeyAndTonic {
    my ($keyNote, $tonicNote) = @_;
    $keyNote   = $keyNote % 12;
    $tonicNote = $tonicNote % 12;
    if ($keyNote > $tonicNote) {
        $tonicNote += 12;
    }

    my $note = $keyNote;
    for (my $i = 0; $i < @gMajorScale; $i++) {
        if ($note == $tonicNote) {
            return $i+1;
        }
        $note += $gMajorScale[$i];
    }
    confess "Failed tonicScaleDegreeFromKeyAndTonic unexpectedly";
}

sub keyAndTonicAgree {
    my ($keyText, $tonicText, $keyNote, $tonicNote) = @_;
    eval {
        tonicScaleDegreeFromKeyAndTonic($keyNote, $tonicNote);
        return;
    };
    if ($@) {
        confess "Key $keyText and tonic $tonicText do not align";
    }
}

sub scaleFromTonic {
    my ($keyNote, $tonicNote, $nnotes) = @_;
    my $tonicScaleDegree = tonicScaleDegreeFromKeyAndTonic($keyNote, $tonicNote);
    my $note = $tonicNote; 
    my @notes;
    for (my $i = 0; $i < $nnotes; $i++) {
        push @notes, $note;
        $note = incrementNoteBasedOnScaleDegree($note, $tonicScaleDegree + $i);
        last if ($note >= 128);
    }
    return @notes;
}

##
## M I D I    W R I T E
##

## midi is a reference that has
##[time, command, arg1, arg2]
## time is in ticks (there are 960 ticks per quarter note)
## Command is one of Note_on_c, Note_off_c, Pitch_bend_c, or Command_c
## for command Note_on_c   -- arg1 is pitch, arg2 is velocity
## for command Note_off_c -- arg1 is pitch, arg2 is 0
## for command Pitch_bend_c -- arg1 is msb of pitch bend, arg2 is the lsb of pitch bend
## for command Command_c    -- arg1 is the CC used, arg2 is the value
sub rawMidiEmit {
    my ($midi, $outputFile) = @_;
    my $channel = 1;
    my $track   = 1;
    my ($fd, $filename) = File::Temp::tempfile(CLEANUP=>0, UNLINK=>0);
    print {$fd} join(', ', 0, 0, 'Header', 1, 1, 960),"\n";
    print {$fd} join(', ', $track, 0, 'Start_track'),"\n";
    my $latestTime = -1;
    for my $row (@$midi) {
        confess "INTERNAL ERROR: row_count=" . scalar(@$row) unless @$row == 4;
        $latestTime = $row->[0] unless $latestTime > $row->[0];
        print {$fd} join(', ', $track, $row->[0], $row->[1], $channel, $row->[2], $row->[3]), "\n";
    }
    print {$fd} join(', ', $track, $latestTime, 'End_track'), "\n";
    print {$fd} join(', ', 0, 0, 'End_of_file'), "\n";
    close($fd);
    run "$gMidiCsvPath $filename > $outputFile";
    unlink $filename;
}

sub emitNote {
    my ($note, $velocity, $duration, $fileName) = @_;
    my @midi = (
        [0,         "Note_on_c",  $note, $velocity],
        [$duration, "Note_off_c", $note, 0],
    );
    rawMidiEmit(\@midi, $fileName);
}

## 
## C O M P U T E    S A M P L E    B O U N D A R I E S
##
## NOTE: all times from this method are measured in seconds.
sub computeSampleBoundaries {
    my ($inputMidiFile, $bpm) = @_;
    my $secondsPerQuarterNote = 60.0/$bpm;
    my $ppqn;
    my (@flagTimes, @noteStarts);

    my @lines = backtick("$gMidiCsvPath $inputMidiFile");
    chomp(@lines);
    
    for my $line (@lines) {
        my @fields = split ",", $line;
        for (@fields) {
            s/^\s*//;
            s/\s*$//;
        }
        my $command = $fields[2];
        if ($command eq 'Header') {
            $ppqn = $fields[5];
        } elsif ($command eq 'Note_on_c') {
            my (undef, $ticks, $command, $channel, $pitch, $velocity) = @fields;
            if ($velocity != 0) {
                confess "Unable to find ppqn in file $inputMidiFile" unless defined($ppqn);
                my $time = ($ticks/$ppqn)*$secondsPerQuarterNote;
                if ($pitch == $gFlagPitch) {
                    push @flagTimes, $time;
                } else {
                    push @noteStarts, $time;
                }
            }
        }
    }

    confess "Failed to find any flag notes in $inputMidiFile" unless @flagTimes > 0;
    printf("Processing %d samples\n", scalar(@flagTimes)) if $gVerbose;

    my @sampleBoundaries;
    while (@flagTimes > 0 && @noteStarts > 0) {
        my $flag = shift @flagTimes;
        while (@noteStarts > 0) {
            my $time = shift @noteStarts;
            if ($time >= $flag) {
                push @sampleBoundaries, $time;
                last;
            }
        }
    }
    confess "Unmatched flagTimes found" if @flagTimes > 0 && @noteStarts == 0;
    return \@sampleBoundaries;
}

##
## S P L I T   A U D I O   F I L E
##
sub splitAudioFile {
    my ($inputWavFile, $sampleBoundaries, $outputDir) = @_;
    my @boundaries = @$sampleBoundaries;
    my $timeStamp = time;
    my @letters = ('A' .. 'Z');
    my $count = 0;
    my $sourceTag = $inputWavFile;
    $sourceTag =~ s/\.wav$//;
    $sourceTag =~ s/^input\///;
    my $nboundaries = scalar(@$sampleBoundaries);
    for (my $i = 0; $i < $nboundaries; $i++) {
        my $start = $boundaries[$i]; 
        my $duration = "";
        if ($i+1 < $nboundaries) {
            $duration = $boundaries[$i+1] - $start;
        }
        my $orderTag = $letters[$i / 26] . $letters[$i % 26];
        my $outputWavFile = "$outputDir/$timeStamp.$orderTag.$sourceTag.wav";
        run "$gSoxPath $inputWavFile $outputWavFile trim $start $duration";
    }
}

##
## C O M M A N D S
##
sub commandNoteRange {
    my ($keyText, $tonicText, $velocity, $framesOfNotes, $duration) = @_;
    confess "Note enough arguments to noteRange" unless defined($keyText) && defined($tonicText);
    my $keyNote   = text2Note($keyText);
    my $tonicNote = text2Note($tonicText);
    keyAndTonicAgree($keyText, $tonicText, $keyNote, $tonicNote);
    $velocity      = 90 unless defined($velocity);
    confess "Bad velocity argument to noteRange '$velocity'" 
        unless ($velocity =~ /^\d+$/ && $velocity > 0 && $velocity < 128);
    $framesOfNotes = 1 unless defined($framesOfNotes);
    confess "Bad argument to noteRange for framesOfNotes '$framesOfNotes'"
        unless ($framesOfNotes =~ /^\d+$/ || $framesOfNotes < 1 || $framesOfNotes > 7);
    my $duration = 4*960;
    my @notes = scaleFromTonic($keyNote, $tonicNote, $framesOfNotes*16);

    my @letters = ('A' .. 'Z');
    my $row = 1;
    my $col = 1;
    for (my $i = 0; $i < 16*$framesOfNotes; $i++) {
        my $leftTag  = $letters[$i / 26];
        my $rightTag = $letters[$i % 26];

        if ($i >= @notes) {
            printf "noteRange ran out of notes $i (%d)\n", 16*$framesOfNotes;
            return;
        }
        my $noteText = note2Text($notes[$i]);
        my $fname = "output/${leftTag}${rightTag}.${row}x${col}_n${noteText}.mid";
        emitNote($notes[$i], $velocity, $duration, $fname);

        $col++;
        if ($col > 4) {
            $col = 1;
            $row++;
            if ($row > 4) {
                $row = 1;
            }
        }
    }
}

sub commandRenameFreeze {
    my @list = grep { /^Freeze.*\.wav/ } map { s/^input\/// } backtick("ls input/*.wav");

    my $blankFound;
    my %order;
    for my $l (@list) {
        my ($index) = ($l =~ /-(\d+).wav$/);
        if (!defined($index)) {
            confess "renameFreeze found too many un-indexed file names looking at '$l'" if $blankFound;
            $blankFound = 1;
            $index = -1;
        }
        $order{$l} = $index;
    }

    @list = sort {$order{$a} <=> $order{$b}} @list;

    my $timestamp = time;
    my @letters = ('A' .. 'Z');
    for (my $i = 0; $i < @list; $i++) {
        
        my $leftTag  = $letters[$i / 26];
        my $rightTag = $letters[$i % 26];

        my $ofile = "output/${leftTag}${rightTag}.$timestamp.wav";
        my $ifile = "input/$list[$i]";
        run "mv $ifile $ofile";
    }
}

sub commandSplitKit {
    my ($tag) = @_;
    $tag =~ s/^input\///;
    $tag =~ s/\.$//;
    my $inputYamlFile = "input/$tag.yaml";
    my $inputMidiFile = "input/$tag.mid";
    my $inputWavFile  = "input/$tag.wav";
    
    confess "Couldn't find input json file $inputYamlFile" unless -f $inputYamlFile;
    confess "Couldn't find input midi file $inputMidiFile" unless -f $inputMidiFile;
    confess "Couldn't find input wav file $inputWavFile" unless -f $inputWavFile;

    my $conf = YAML::LoadFile($inputYamlFile);
    my $bpm  = $conf->{bpm};
    confess "Config file $inputYamlFile did NOT correctly define mandatory config option bpm" 
        unless defined($bpm) && $bpm > 20 && $bpm < 180;

    my $boundaries = computeSampleBoundaries($inputMidiFile, $bpm);
    splitAudioFile($inputWavFile, $boundaries, "output");
}

##
## Utilities
##
sub removeTagged {
    my @list = grep {/^[A-Z][A-Z]\./} 
                map { s/^output\///; $_ } (backtick("ls output/*.mid 2> /dev/null", noexit=>1),
                                           backtick("ls output/*.wav 2> /dev/null", noexit=>1));
    for (@list) {
        unlink "output/$_";
    }
}


my %gCommands = (
    noteRange => \&commandNoteRange,
    renameFreeze => \&commandRenameFreeze,
    splitKit => \&commandSplitKit,
);

sub main {
    my ($command, @args) = @ARGV;

    confess "Requires 1 argument" unless defined($command);
    confess "Unknown command" unless defined($gCommands{$command});

    ## Clear existing files
    removeTagged();

    ## Build input/output directory
    run "mkdir -p input";
    run "mkdir -p output";

    ## Run the command
    $gCommands{$command}(@args);
}

main();