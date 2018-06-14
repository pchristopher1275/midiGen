use strict;
use Data::Dumper;
use Carp;
use File::Temp;

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
##      noteRange <Key-Note> <Tonic-Note> [Velocity:90] [numberOfFrames:2] [Duration:4*960]
##      renameFreeze
## Examples:
##      noteRange G3 F
## P R O C E S S   R U N N I N G
##
sub backtick {
    my ($command) = @_;
    my @lines = `$command`;
    if ($?) {
        confess "Failed '$command': $!";
    }
    chomp(@lines);
    return @lines;
}

sub run {
    my ($cmd) = @_;
    if (system $cmd){
        confess "Failed: '$cmd': $!";
    }
}

## 
## K E Y
##
my @gMajorScale = (2, 2, 1, 2, 2, 2, 1);
my @gNoteSymbols = qw/ C   C#  D  D#  E   F   F#  G  G#  A A# B  /;
my $gCsvMidiPath = "foo";

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
    $l =~ s/s/#/; ## We accept s for # -- so it's nicer to work with on command line
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
    return $tonicNote - $keyNote + 1;
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
    run "$gCsvMidiPath $filename > $outputFile";
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
## C O M M A N D S
##
sub commandNoteRange {
    my ($keyText, $tonicText, $velocity, $framesOfNotes, $duration) = @_;
    confess "Note enough arguments to noteRange" unless defined($keyText) && defined($tonicText);
    my $keyNote   = text2Note($keyText);
    my $tonicNote = text2Note($tonicText);
    $velocity      = 90 unless defined($velocity);
    confess "Bad velocity argument to noteRange '$velocity'" 
        unless $velocity =~ /^\d$/ && $velocity > 0 && $velocity < 128;
    $framesOfNotes = 2 unless defined($framesOfNotes);
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
            print "noteRange ran out of notes\n";
            return;
        }

        my $fname = "output/${leftTag}${rightTag}.${row}x${col}_n${keyText}_${tonicText}.mid";
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

##
## Utilities
##
sub removeTagged {
    my @list = grep {/^[A-Z][A-Z]\./} map { s/^output\/// } backtick("ls output/*.mid output/*.wav");
    print "@list\n";
    # unlink @list;
}


my %gCommands = (
    noteRange => \&commandNoteRange,
    renameFreeze => \&commandRenameFreeze,
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