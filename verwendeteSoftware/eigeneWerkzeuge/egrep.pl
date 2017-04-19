#!/usr/local/bin/perl
#
#	Thomas Felden
# 14.6.2010
#
# Das Programm verwendet den Ausdruck und liefert die Zeilen, die dazu passen

use Encode;
use Encode::Guess;
use Getopt::Long;
use Data::Dumper;
use strict;
use File::Basename;
use File::Spec;
Getopt::Long::Configure ("bundling");

our $verbose = 0;
our @dateinamen = ();						# Diese Dateien in dieser Reihenfolge untersuchen
our $filterdatei = "";					# Dies ist die Datei mit den Filtern bzw. Mustern
our $filterausdruck = sub { die "falsche Funktion verwendet\n"; }; 
																# ist eine Referenz auf eine Funktion, die prüft, ob die Eingabezeile zu einem der angegebenen Ausdrücke paßt
																# Die Funktion verwendet $_ als zu untersuchende Zeile
																# Die Funktion liefert Array aus zwei Elementen:
																#   0 <=> die Zeile paßt zu einem der Muster, 1 sonst
																#		Den erkannten Teil
my $ausgabedatei = "";					# In diese Datei soll das Ergebnis geschrieben werden. Falls nicht angegeben in stdout schreiben
our $anzahlVorlaufzeilen = 0;		# soviel Zeilen sollen vor einer Fundstelle ausgegeben werden
our $anzahlNachlaufzeilen = 0;	# soviel Zeilen sollen nach einer Fundstelle ausgegeben werden
our $bytePositionAusgeben = 0;	# Die Position der Fundstelle wird in Bytes angegeben und mit einem Doppelpunkt ausgegeben. 1 ist das erste Byte in einer Datei.
																# Die Byteposition wird hinter einer Zeilennummer ausgegeben.
my $anzahlUmgebungszeilen = 0;	# Soviel Zeilen sollen vor und hinter der Fundstelle ausgegeben werden
my $nurZaehlen = 0;							# 1 <=> Nur die Anzahl passender Zeilen je Datei ausgeben. Dateien ohne passende Zeilen werden nicht ausgegeben.
																# 0 sonst. (Die passenden Zeilen werden ausgegeben)
my $keinMuster = 0;							# 1 <=> Das Muster enthält unter Umständen mehrere Zeilen. Dann werden die Muster jeder Zeile oderverknüpft. Wird nur verwendet, wenn auch -f gesetzt ist
																# 0 sonst.
our $dateinamenAusgeben = 0;		# 1 <=> Der Dateiname soll vor jede Fundstelle ausgegeben werden. Der Dateiname wird mit einem eventuellen Pfad und einem abschließenden Doppelpunkt am Zeilenanfang ausgegeben.
my $versionAusgeben = 0;
my $hilfeAusgeben = 0;
our $schreibungIgnorieren = 0;	# 1 <=> es wird nicht zwischen Groß- und Kleinbuchstaben unterschieden
my $nurDateinamenAusgeben = 0;	# 1 <=> nur die Dateinamen werden ausgegeben, wenn dort eine Zeile paßt. 0 sonst
my $LGesetzt = 0;
my $lGesetzt = 0;
our $zeilenPositionAusgeben = 0;# Die Position der Fundstelle wird als Zeilennummer angegeben und mit einem Doppelpunkt ausgegeben. 1 ist die erste Zeile in einer Datei.
																# Wird auch der Dateiname ausgegeben, so folgt die Zeilennummer dem Dateinamen.
my $nurPassendesAusgeben = 0;		# 1 <=> nur der Text, welcher vom Muster erkannt wurde, ausgeben. 0 die ganze Zeile wird ausgegeben
my $muster = '';
our $rekursiv = 0;							# 1 <=> auch alle Unterverzeichnisse durchsuchen. 0 sonst
my $musterDateienEinbeziehen = '';		# Die Dateien passend zu diesem Muster sind im angegebenen Verzeichnis zu durchsuchen
my $musterDateienAusschliessen = '';	# Die Dateien welche zu diesem Muster passen werden während der Suche ignoriert
our $fehlerUnterdruecken = 0;		# 1 <=> Fehlermeldungen zu nicht lesbaren oder nicht existierenden Dateien werden unterdrückt
my $versionAusgeben = 0;				# 1 <=> Nur die Version soll ausgegeben werden (Eine Suche findet nicht statt)
my $invertieren = 0;						# 1 <=> Zeilen, die nicht passen werden so behandelt, wie wenn sie passen würden und vice versa. 0 sonst
my $nurGanzeWoerter = 0;				# 1 <=> Der erkannte Textabschnitt muß an einer Wortgrenze beginnen und mit einer Wortgrenze enden.
my $nurGanzeZeile = 0;					# 1 <=> Der erkannte Textabschnitt muß die ganze Zeile sein
my $externesVerbose = 0;				# 1 <=> Verbose soll angeschaltet werden
my $kodiert = '';								# wenn nichts angegeben wurde, wird daraus utf8

# wie die aber gibt die Information auch auf die Standardausgabe aus
sub geheSterben {
	my ($fehler) = @_;
  my $trace = Devel::StackTrace->new;
  $fehler .= "\n$trace->as_string";
	#  while (my $frame = $trace->next_frame) {
	#	  print "Has args\n" if $frame->hasargs;
	#  }
	print encode('cp850',$fehler); 
	die encode('cp850',$fehler); 
}

# Untersucht eine Anzahl von Dateien und oder Verzeichnissen und liefert alle enthaltenen Dateinamen.
# Die Dateinamen sind innerhalb des Verzeichnisses alphabetisch sortiert.
# Parameter
#		aufzuloesen
#			Dies ist ein Array von Datei oder Verzeichnisnamen bzw. globs.
# Seiteneffekt
#		Fügt die gefundenen Dateien an die das globale Array dateien an
#
sub loeseGlobsAuf {
	print "loeseGlobsAuf(" . join(', ',@_) . ")...\n" if $verbose;
	my $aufzuloesen;
	my @enthalten = ();
	my @sortiert = ();
	foreach $aufzuloesen (@_) {
		#print "$aufzuloesen = " . ( (-f $aufzuloesen)?"Datei":((-d $aufzuloesen)?"Verzeichnis":"glob")) . "\n";
		# ist es eine Datei?
		if ( -f $aufzuloesen ) {
			if ( -r $aufzuloesen ) {
				# ist eine lesbare Datei
				push @dateinamen, $aufzuloesen;
			} elsif ( 0 == $fehlerUnterdruecken ) {
				print stderr "Konnte Datei ($aufzuloesen) nicht lesen\n";
			}
		} elsif ( -d $aufzuloesen ) {
			if ($rekursiv) {
				if ( -r $aufzuloesen ) {
					# ist ein lesbares Verzeichnis
					if ( ! opendir DIR, $aufzuloesen ) {
						if ( 0 == $fehlerUnterdruecken ) {
							print stderr "Konnte Verzeichnis ($aufzuloesen) nicht öffnen\n";
						}
					} else {
						@enthalten = grep !/^\.\.?\z/,readdir DIR;	# . und .. ignorieren
						closedir DIR;
						#print "Verzeichnis $aufzuloesen lokal aufgelöst => \n" . join("\n",@enthalten) . "\n";
						@enthalten = map {File::Spec->catfile($aufzuloesen, $_)} @enthalten;
						#print "Verzeichnis $aufzuloesen sortiert aufgelöst => \n" . join("\n",@enthalten) . "\n";
						loeseGlobsAuf(@enthalten);
					}
				} elsif ( 0 == $fehlerUnterdruecken ) {
					print stderr "Konnte Datei ($aufzuloesen) nicht lesen\n";
				}
			}
		} else {
			# hier versuchen dies als glob zu sehen
			@enthalten = glob($aufzuloesen);
			if ( $#enthalten > 0 ) {
				loeseGlobsAuf(sort @enthalten);
			} elsif ( $#enthalten == 0 && $aufzuloesen eq $enthalten[0] ) {
				print stderr "Datei $aufzuloesen konnte nicht gefunden werden\n" if ! $fehlerUnterdruecken;
			} else {
				print stderr "Konnte keine Datei zu $aufzuloesen finden\n" if ! $fehlerUnterdruecken;
			}
		}
	}
	return 1;
}

sub parameterBeschreiben { 
	my ($fehler) = @_; 
	$_ = "Achtung: $fehler!\n" . <<Textende; 
grep [options] [-p PATTERN | -f FILE] [FILE...]
grep searches the named input FILEs (or standard input if no files are named, 
or the file name - is given) for lines containing a match to the given PATTERN. 
By default, grep prints the matching lines.
Dies ist eine Untermenge von dem unter Unix bekannten grep. Nicht implementiert 
bedeutet dabei, daß diese Funktionalität später nachgeliefert wird.
	
-a Dateiname --ausgabe=Dateiname
  Schreibt das Ergebnis in Dateiname anstatt es auf die Standardausgabe zu 
  leiten.
-A NUM, --after-context=NUM
  Print NUM lines of trailing context after matching lines. Places a line 
  containing -- between contiguous groups of matches. Hat Priorität über -C.
-B NUM, --before-context=NUM
  Print NUM lines of leading context before matching  lines. Places a line 
  containing -- between contiguous groups of matches. Hat Priorität über -C.
-b, --byte-offset
  Print the byte offset within the input file before each line of output.
-C NUM, --context=NUM
  Print NUM lines of output context. Places a line containing -- between 
  contiguous groups of matches. Zeilen werden beginnend mit 1 gezählt.
-c, --count
  Suppress normal output; instead print a count of matching lines for each input
  file. Hat Priorität über -A und -B.
-F, --fixed-strings (nicht implementiert)
  Interpret PATTERN as a list of fixed strings, separated by newlines, any of 
  which is to be matched. Wird nur verwendet, wenn das Muster aus einer Datei 
  gelesen wird.
-f FILE, --file=FILE
  Obtain patterns from FILE, one per line.  The empty file contains zero 
  patterns, and therefore matches nothing. Darf nur verwendet werden, wenn
  -p nicht verwendet wurde. Jede Zeile enthält eine oder mehrere durch && 
  getrennte Perlausdrücke. Leerzeilen und Zeilen, die von einem # 
  angeführt werden, werden ignoriert.
-H, --with-filename
  Print the filename for each match.
-h, --help 
  Output a brief help message.
-i, --ignore-case
  Ignore case distinctions in both the PATTERN and the input files.
-k, --kodiert
  Gibt an, in was der Input kodiert ist. Falls nichts angegeben wird, wird utf8
  angenommen.
-L, --files-without-match
  Suppress  normal  output; instead print the name of each input file from which 
  no output would normally have been printed. Gibt genau dann einen Namen aus, 
  wenn -l keinen Namen ausgeben würde. Falls diese Option angegeben wird, werden 
  die Optionen -A, -B, -b, -C, -c, -n und -o ignoriert.
-l, --files-with-matches
  Suppress  normal  output; instead print the name of each input file from which 
  output would normally have been printed. The scanning will stop on the first 
  match. Falls diese Option angegeben wird, werden die Optionen -A, -B, -b,
  -C, -c, -n und -o ignoriert.
-n, --line-number
  Prefix each line of output with the line number within its input file.
-o, --only-matching
  Show only the part of a matching line that matches PATTERN. Wird eine Zeile 
  von mehreren Mustern getroffen, dann wird der Zeilenabschnitt ausgegeben 
  welcher zum ersten passenden Muster gehört. Werden die nicht passenden
  Zeilen angezeigt, so wird immer die ganze Zeile ausgegeben.
-p, -P, --perl-regexp
  Interpret PATTERN as a Perl regular expression.
-r, -R, --recursive
  Read all files under each directory, recursively
--include=PATTERN
  Nur Dateien beachten, die diesem Muster entsprechen.
--exclude=PATTERN
  Von den ausgewählten Dateien die diesem Muster Entsprechenden ignorieren.
  Die Voreinstellung ist keine Dateien auszuschließen.
  Zuerst werden die angegebenen Dateien zusammengestellt, dann werden gemäß 
  --include davon Dateien ausgewählt und abschließend gemäß --exclude 
  dann Dateien von der Betrachtung ausgenommen.
-s, --no-messages
  Suppress error messages about nonexistent or unreadable files.
-V, --version
  Gibt die Version des Programms aus. 
-v, --invert-match
  Invert the sense of matching, to select non-matching lines.
--verbose
	Dokumentiere die Verarbeitung.
-w, --word-regexp (nicht implementiert)
  Select only those lines containing matches that form whole words. The test is 
  that the matching substring must either be at the beginning of the line, or 
  preceded by a non-word constituent character. Similarly, it must be either at 
  the end of the line or followed by a non-word constituent character. 
  Wordconstituent characters are letters, digits, and the underscore.
-x, --line-regexp
  Select only those matches that exactly match the whole line. Es wird nur untersucht,
  ob der erste passende Ausdruck die gesamte Zeile trifft. Könnte ein weiterer 
  Ausdruck die gesamte Zeile treffen, dann wird dieser trotzdem nicht verwendet.
  Der Anwender muß die Ausdrücke entsprechend angeben, damit dies gewährleistet ist.
-y
  Synonym für -i.
Textende
  if ( utf8::valid($_) ) {
  	#print "Text ist im utf8 Format\n";
		utf8::decode($_); 
	}
	print encode('cp850',$_);
exit 0;
}

GetOptions(
	'a=s' => \$ausgabedatei, 'ausgabe=s' => \$ausgabedatei, 
	'A=i' => \$anzahlNachlaufzeilen, 'after-context=i' => \$anzahlNachlaufzeilen, 
	'B=i' => \$anzahlVorlaufzeilen, 'before-context=i' => \$anzahlVorlaufzeilen, 
	'b' => \$bytePositionAusgeben, 'byte-offset' => \$bytePositionAusgeben, 
	'C=i' => \$anzahlUmgebungszeilen, 'context=i' => \$anzahlUmgebungszeilen,
	'c' => \$nurZaehlen,
	'F' => \$keinMuster, 'fixed-strings' => \$keinMuster, 
	'f=s' => \$filterdatei, 'file=s' => \$filterdatei, 
	'H' => \$dateinamenAusgeben, 'with-filename' => \$dateinamenAusgeben, 
	'h' => \$hilfeAusgeben, 'help' => \$hilfeAusgeben,
	'i' => \$schreibungIgnorieren, 'y' => \$schreibungIgnorieren, 'ignore-case' => \$schreibungIgnorieren, 
	'k=s' => \$kodiert, 'kodiert=s' => \$kodiert, 
	'L' => \$LGesetzt, 'files-without-match' => \$LGesetzt, 
	'l' => \$lGesetzt, 'files-with-matches' => \$lGesetzt, 
	'n' => \$zeilenPositionAusgeben, 'line-number' => \$zeilenPositionAusgeben, 
	'o' => \$nurPassendesAusgeben, 'only-matching' => \$nurPassendesAusgeben, 
	'p=s' => \$muster, 'P=s' => \$muster, 'perl-regexp=s' => \$muster, 
	'r' => \$rekursiv, 'R' => \$rekursiv, 'recursive' => \$rekursiv, 
	'include=s' => \$musterDateienEinbeziehen,
	'exclude=s' => \$musterDateienAusschliessen,
	's' => \$fehlerUnterdruecken, 'no-messages' => \$fehlerUnterdruecken, 
	'V' => \$versionAusgeben, 'version' => \$versionAusgeben, 
	'v' => \$invertieren, 'invert-match' => \$invertieren, 
	'verbose' => \$externesVerbose,
	'w' => \$nurGanzeWoerter, 'word-regexp' => \$nurGanzeWoerter, 
	'x' => \$nurGanzeZeile, 'line-regexp' => \$nurGanzeZeile
);
$verbose |= $externesVerbose;
*AH = *STDOUT;
if ($ausgabedatei ne "") {
	open(AH,"> $ausgabedatei") or geheSterben "Konnte Datei $ausgabedatei nicht zum Schreiben öffnen: $!\n";
}
if ($verbose) {
	print "Erkannte Parameter: ";
	print "-a $ausgabedatei " if $ausgabedatei ne '';
	print "-A $anzahlNachlaufzeilen " if $anzahlNachlaufzeilen > 0;
	print "-B $anzahlVorlaufzeilen " if $anzahlVorlaufzeilen > 0;
	print "-b " if $bytePositionAusgeben;
	print "-C $anzahlUmgebungszeilen " if $anzahlUmgebungszeilen > 0;
	print "-c " if $nurZaehlen;
	print "-F " if $keinMuster;
	print "-f $filterdatei " if $filterdatei ne '';
	print "-H " if $dateinamenAusgeben;
	print "-h " if $hilfeAusgeben;
	print "-i " if $schreibungIgnorieren;
	print "-k $kodiert " if $kodiert;
	print "-L " if $LGesetzt;
	print "-l " if $lGesetzt;
	print "-n " if $zeilenPositionAusgeben;
	print "-o " if $nurPassendesAusgeben;
	print "-p " . $muster . " " if $muster ne '';
	print "-r " if $rekursiv;
	print "--include " . $musterDateienEinbeziehen . " " if $musterDateienEinbeziehen ne '';
	print "--exclude " . $musterDateienAusschliessen . " " if $musterDateienAusschliessen ne '';
	print "-s " if $fehlerUnterdruecken;
	print "-V " if $versionAusgeben;
	print "-v " if $invertieren;
	print "-w " if $nurGanzeWoerter;
	print "-x " if $nurGanzeZeile;
	print "Restliche Parameter = (" . join(', ',@ARGV) . ")" if -1 < $#ARGV;
	print "\n";
}	
parameterBeschreiben("Hilfe angefordert") if $hilfeAusgeben;
if ($versionAusgeben) {
	print "Version 26.8.2010 7:43\n";
	exit 0;
}
$kodiert = 'utf8' if $kodiert eq '';
my @bekannteEncodings = Encode->encodings();
my $encodingIstGueltig = 0;
#print "Gültige Encodings:\n";
foreach (sort @bekannteEncodings) {
	#print "  $_.\n";
	$encodingIstGueltig = 1 if $_ eq $kodiert;
}
parameterBeschreiben("Das angegebene Encoding ($kodiert) ist unzulässig. Bitte wählen Sie eines aus (" . join(', ', @bekannteEncodings) . ") aus") if ! $encodingIstGueltig;
$kodiert = ":$kodiert";

$nurDateinamenAusgeben = $LGesetzt || $lGesetzt;
if ( $nurDateinamenAusgeben ) {
	print "Die Optionen -A, -B, -b, -C, -c, -n und -o werden ignoriert\n" if $verbose;
	$anzahlNachlaufzeilen = 0;
	$anzahlVorlaufzeilen = 0;
	$bytePositionAusgeben = 0;
	$anzahlUmgebungszeilen = 0;
	$nurZaehlen = 0;
	$zeilenPositionAusgeben = 0;
	$nurPassendesAusgeben = 0;
}
parameterBeschreiben("Die angegebene Zeilenzahl zu Option A muß eine positive ganze Zahl sein") if $anzahlNachlaufzeilen < 0;
parameterBeschreiben("Die angegebene Zeilenzahl zu Option B muß eine positive ganze Zahl sein") if $anzahlVorlaufzeilen < 0;
parameterBeschreiben("Die angegebene Zeilenzahl zu Option C muß eine positive ganze Zahl sein") if $anzahlUmgebungszeilen < 0;
$anzahlVorlaufzeilen = $anzahlUmgebungszeilen if 0 == $anzahlVorlaufzeilen;
$anzahlNachlaufzeilen = $anzahlUmgebungszeilen if 0 == $anzahlNachlaufzeilen;
parameterBeschreiben("Option F nicht implementiert") if 0 != $keinMuster;
parameterBeschreiben("Option w nicht implementiert") if $nurGanzeWoerter;
parameterBeschreiben("Optionen -p und -f können nicht gleichzeitig verwendet werden") if ($muster ne '' && $filterdatei ne '');
parameterBeschreiben("Entweder -p oder -f muß angegeben werden") if ($muster eq '' && $filterdatei eq '');

# Wandelt den Inhalt der Filterdatei in eine Funktion für den filterausdruck um
# Die erzeugte Funktion verwendet $_ als zu untersuchende Zeile
# und liefert 0 <=> die Zeile paßt zu einem der Muster, 1 sonst
sub wandleFilterdatei {
	my ($datei) = @_;
	my $zeile;
	my $bedingung;
	my $anzahlBedingungen;
	my $zeilennr = 0;
	my $funktion = "\$filterausdruck = sub {\n  my (\$verbose) = \@_;\n  my \$zuSpeichern = 0;\n  my \$erkannt = \'\';\n";
	$funktion .= "  print \"filterausdruck prüft (\$_)...\\n\" if (\$verbose);\n";
	open(FH,$datei) or die "Konnte Datei $datei nicht zum Schreiben öffnen: $!\n";
	while(defined($zeile = <FH>)) { 
		$zeilennr++;
		$funktion .= sprintf("# %3d: $zeile", $zeilennr);
		if ($zeile !~ /^\s*(?:#.*)?$/ ) {
			chomp $zeile;
			$funktion .= "  # Prüfe ob Gesamtbedingung ($zeile) erfüllt ist\n  if ( (0 == \$zuSpeichern)";
			$anzahlBedingungen = 0;
			foreach $bedingung (split /\s*&&\s*/, $zeile) {
				$anzahlBedingungen++;
				#$funktion .= "    # Prüfe ob Teil $anzahlBedingungen = ($bedingung) erfüllt ist\n";
				$funktion .= " && (\$_ =~ /$bedingung/" . ($schreibungIgnorieren?'i':'') . ")";
			}
			$funktion .= " ) {\n    \$zuSpeichern = 1; \$erkannt = \$&; print \"Bedingung ($zeile) paßt\\n\" if \$verbose;\n  }\n";
		}
	}
	close FH;
	$funktion .= "  return (\$zuSpeichern, \$erkannt);\n};\n";
	return $funktion;
}

if (0) {
	# Inhalt der Filterdatei:
	## Filterdatei egrep
	#
	#(?<!\d)\d\d(?!\d)
	#speise
	#[a-wyzA-WYZäÄöÖüÜß] && [a-zA-ZäÄöÖüÜß]+
	#[a-wyzA-WYZäÄöÖüÜß] && ^\w+
	$verbose = 1;
	print "# teste wandleFilterdatei...\n";
	if ($filterdatei ne "") {
		my $erzeugteFiltersub = wandleFilterdatei($filterdatei);
		print "# Erzeugte Testfunktion:\n" . $erzeugteFiltersub;
		eval $erzeugteFiltersub;
	} else {
		parameterBeschreiben("Die Filterdatei muß angegeben werden");		
	}
	my @positiveTestfaelle = (
		"hier 12",
		"hallo 2345",
		"götterspeise",
		"neukölln 459856 haupt",
		"yy--43",
		"rt",
		"hauptSpeise"
	);
	my @negativeTestfaelle = (
		"xxxxxx",
		"43566",
		"====="
	);
	my %testfaelle = ();
	foreach (@positiveTestfaelle) {
		$testfaelle{$_} = 1;
	}
	foreach (@negativeTestfaelle) {
		$testfaelle{$_} = 0;
	}
	my ($ist, $erkannt);
	my $zeilennr = 1;
	my $fehlerhaft = 0;
	foreach (sort keys %testfaelle) {
		print "prüfe Zeile:$_. =>";
		$zeilennr++;
		$verbose = 0;
		($ist, $erkannt) = $filterausdruck->($verbose);
		$verbose = 0;
		print " " . ($ist?"paßt":"ignorieren") . " => ";
		if ( $ist != $testfaelle{$_} ) {
			print "nicht erwartet\n";
			$fehlerhaft++;
		} else {
			print "ok - gefunden: ($erkannt)\n";
		}
	}
	if ( 1 == $fehlerhaft ) {
		print "\nTest entdeckte einen Fehler\n";
	} elsif ( $fehlerhaft > 1 ) {
		print "\nTest entdeckte $fehlerhaft Fehler\n";
	} else {
		print "\nTest OK\n";
	}
	exit 0;
}

# Prüft, ob die Zeile an Position letzteGueltige auch dann ausgedruckt werden soll, wenn sie nicht paßt
# Parameter
#		passt
#			Referenz auf einen Array mit folgender Information:
#				Bit 0 gesetzt <=> zeile in zeilen ist gemäß Muster und Parameter gewählt
#				Bit 1 gesetzt <=> Zeile ist zu drucken
#		ersteGueltige
#			Dies ist die erste gültige Zeileninformation in passt
#			Falls ersteGueltige > -1, dann sind die folgenden Zeilen in dieser Reihenfolge gültig:
#			1. Falls ersteGueltige <= letzteGueltige, dann die Zeilen ersteGueltige bis letzteGueltige
#			2. Sonst die Zeilen ersteGueltige bis zeilenSollgroesse-1 und dann von 0 bis letzteGueltige.
#		letzteGueltige
# 		Dies ist die letzte gültige Zeileninformation in passt
#		max
#			Dies ist der maximal für letzteGueltige zulässige Wert
# Ergebnis
#		Liefert 1 <=> die Zeile an der Stelle letzteGueltige soll gedruckt werden, obwohl sie nicht passt. 0 sonst
#
sub istImNachlaufVonTreffer {
	my ($passt, $ersteGueltige, $letzteGueltige, $max) = @_;
	my $zuDrucken = 0;
	# genau dann drucken, wenn innerhalb der vorherigen $anzahlNachlaufzeilen eine passende Zeile steht
	my $i = $letzteGueltige-1;
	my $j = $anzahlNachlaufzeilen;
	while ($j && ! $zuDrucken) {
		$i = $max if $i < 0;
		$zuDrucken = 1 if ${$passt}[$i] & 1;
		$i--;
		$j--;
	}
	return $zuDrucken;
}

# Gibt die Zeile aus
# Falls eine Umgebung ausgegeben werden soll, dann wird vor die passende Zeile ein * und sonst ein Leerzeichen geschrieben
# Parameter
#		dateiname
#		zeilennr
#		bytePosition
#		zeile
#		passt
#			Bit 0 gesetzt <=> zeile in zeilen ist gemäß Muster und Parameter gewählt
#			Bit 1 gesetzt <=> Zeile ist zu drucken
#
# Ergebnis
#		Gibt die Zeile entsprechend der Parameter formatiert aus
#
sub zeileAusgeben {
	my ($dateiname, $zeilennr, $bytePosition, $zeile, $passt) = @_;
	my $ergebnis = "";
	if ( $anzahlVorlaufzeilen || $anzahlNachlaufzeilen ) {
		if ( $passt & 1 ) {
			$ergebnis .= '*';
		} else {
			$ergebnis .= ' ';
		}
	}
	$ergebnis .= $dateiname . ':' if $dateinamenAusgeben;
	$ergebnis .= "$zeilennr:" if $zeilenPositionAusgeben;
	$ergebnis .= "$bytePosition:" if $bytePositionAusgeben;
	$ergebnis .= "$zeile\n";
	print $ergebnis;
}

# Die Dateien bestimmen, die durchsucht werden sollen
# In ARGV stehen die Dateien oder Verzeichnisse
# Falls rekursiv vorgegangen werden soll, ermittle zu jedem Verzeichnis alle Unterverzeichnisse
# Ermittle alle Dateien zu allen Verzeichnissen. Damit ergibt sich eine Liste aller zu durchsuchenden Dateien
# Ignoriere die Dateien, die mit --include nicht ausgewählt sind
# Ignoriere die Dateien, die mit --exclude ausgewählt sind
loeseGlobsAuf(@ARGV);
if ($verbose && $#dateinamen >= 0) {
	print "Dateien nach dem Auflösen:\n";
	foreach (@dateinamen) {
		print "  $_\n";
	}
}
my $i;
my $verzeichnis;
if ( $musterDateienEinbeziehen ne '' ) {
	for ($i = $#dateinamen; $i >= 0; $i--) {
		# nur der Dateiname, nicht aber der Pfad wird untersucht
		($_, $verzeichnis, undef) = $dateinamen[$i];
		if ( ! /$musterDateienEinbeziehen/o ) {
			# diese Datei ignorieren
			print "ignoriere $_ ($dateinamen[$i]) wegen --include\n" if $verbose;
			splice @dateinamen, $i, 1;
		}
	}
	if ($verbose) {
		print "\nDateien nach Verarbeitung von --include:\n";
		foreach (@dateinamen) {
			print "  $_\n";
		}
	}
}
if ( $musterDateienAusschliessen ne '' ) {
	for ($i = $#dateinamen; $i >= 0; $i--) {
		# nur der Dateiname, nicht aber der Pfad wird untersucht
		($_, $verzeichnis, undef) = $dateinamen[$i];
		if ( /$musterDateienAusschliessen/o ) {
			# diese Datei ignorieren
			print "ignoriere $_ ($dateinamen[$i]) wegen --exclude\n" if $verbose;
			splice @dateinamen, $i, 1;
		}
	}
	if ($verbose) {
		print "\nDateien nach Verarbeitung von --exclude:\n";
		foreach (@dateinamen) {
			print "  $_\n";
		}
	}
}
$verbose = 0;

my $dateiname;						# Die aktuelle Datei
my @zeilen = ();					# Hier stehen 1 + $anzahlVorlaufzeilen + $anzahlNachalaufzeilen;
my $zeilenSollgroesse = 1 + $anzahlVorlaufzeilen + $anzahlNachlaufzeilen;
my @passt = ();						# Bit 0 gesetzt <=> zeile in zeilen ist gemäß Muster und Parameter gewählt
													# Bit 1 gesetzt <=> Zeile ist zu drucken
my @bytePos = ();					# Byteposition, an der die Zeile beginnt
my @zeilennr = ();				# Zeilennummer der Zeile
my $letzteBytePos;
my $ersteGueltige = -1;		# Dies ist die erste gültige Zeile in zeilen
my $letzteGueltige = -1; 	# Dies ist die letzte gültige Zeile in zeilen
													# Falls ersteGueltige > -1, dann sind die folgenden Zeilen in dieser Reihenfolge gültig:
													# 1. Falls ersteGueltige <= letzteGueltige, dann die Zeilen ersteGueltige bis letzteGueltige
													# 2. Sonst die Zeilen ersteGueltige bis zeilenSollgroesse-1 und dann von 0 bis letzteGueltige.
my $aktuell = 0; 					# Dies ist die aktuell in Arbeit befindliche Zeile. 
my $nr = 0;								# Zeilennummer der aktuellen Zeile
my $aktuelleByteposition = 0;	# An dieser Byteposition beginnt die aktuelle Zeile
my $erkannterTeil;
my $gesamtGefunden = 0;		# soviele Zeilen passen in allen Dateien
my $inDateiGefunden;			# soviele Zeilen passen in der aktuellen Datei
my ($i, $j);
# Suchausdruck vorbereiten
if ($filterdatei ne '') {
	my $erzeugteFiltersub = $filterausdruck;
	$erzeugteFiltersub = wandleFilterdatei($filterdatei);
	print "# Erzeugte Testfunktion:\n" . $erzeugteFiltersub if $verbose;
	eval $erzeugteFiltersub;
} else {
	$filterausdruck = sub {
	  my ($verbose) = @_;
	  my $zuSpeichern = 0;
	  my $erkannt = '';
	  print "filterausdruck prüft ($_)...\n" if ($verbose);
	  if ( $schreibungIgnorieren ) {
		  if ( /$muster/io ) {
		    $zuSpeichern = 1; $erkannt = $&; print "Bedingung ($muster) paßt\n" if $verbose;
		  }
		} else {
		  if ( /$muster/o ) {
		    $zuSpeichern = 1; $erkannt = $&; print "Bedingung ($muster) paßt\n" if $verbose;
		  }
		}
	  return ($zuSpeichern, $erkannt);
	};
}
foreach $dateiname (@dateinamen) {
	print "Untersuche Datei $dateiname...\n" if $verbose;
	@zeilen = ();						# alte Zeilen löschen
	@passt = ();						
	@bytePos = ();	
	$letzteBytePos = 0;				
	$ersteGueltige = -1;		
	$letzteGueltige = -1; 	
	$aktuell = 0; 					# Dies ist die aktuell in Arbeit befindliche Zeile. 
	$nr = 0;								# Zeilennummer der aktuellen Zeile
	$aktuelleByteposition = 0;	# An dieser Byteposition beginnt die aktuelle Zeile
	$inDateiGefunden = 0;
	open(IH, $dateiname) or geheSterben "Konnte Datei $dateiname nicht zum Lesen öffnen: $!\n";
	binmode IH, "$kodiert";
	while (<IH>) {
		# aktuelle Zeile eintragen
		if (-1 == $ersteGueltige) {
			$ersteGueltige = $letzteGueltige = 0;
		} elsif ( $letzteGueltige == $zeilenSollgroesse-1 ) {
			$letzteGueltige = 0;
		} else {
			$letzteGueltige++;
		}
		$letzteBytePos += length $_;
		$bytePos[$letzteGueltige] = $letzteBytePos;
		chomp;
		$nr++;
		if ( ! utf8::valid $_ ) {
			print "Konnte Zeile $nr nicht decodieren ($_)\n";
			$_ = decode('cp850', $_);
			exit 0;
		}
		$zeilen[$letzteGueltige] = $_;
		$zeilennr[$letzteGueltige] = $nr;
		# prüfen, ob die aktuelle Zeile zu dem angegebenen Muster paßt
		($passt[$letzteGueltige], $erkannterTeil) = $filterausdruck->($verbose);
		$passt[$letzteGueltige] = 0 if $passt[$letzteGueltige] && $nurGanzeZeile && $passt[$letzteGueltige] ne $erkannterTeil;
		$zeilen[$letzteGueltige] = $erkannterTeil if $passt[$letzteGueltige] && $nurPassendesAusgeben && ! $invertieren;
		if ( $invertieren ) {
			if ( $passt[$letzteGueltige] ) {
				$passt[$letzteGueltige] = 0;
			} else {
				$passt[$letzteGueltige] = 3;
			}
		} else {
			$passt[$letzteGueltige] = 3 if $passt[$letzteGueltige];
		}
		
		if ( 3 == $passt[$letzteGueltige] ) {
			$inDateiGefunden++;
			last if $lGesetzt;
		}
		# Ist die aktuelle Zeile zu drucken, auch wenn diese nicht paßt?
		if ($anzahlNachlaufzeilen > 0 && istImNachlaufVonTreffer(\@passt, $ersteGueltige, $letzteGueltige, $zeilenSollgroesse-1) ) {
			$passt[$letzteGueltige] |= 2;
		}
		# Ist ein eventueller Vorlauf zu markieren?
		if ( $anzahlVorlaufzeilen > 0 && ($passt[$letzteGueltige] & 1)) {
			# entsprechend viele vorherigen Zeilen zum Drucken markieren
			$j = $anzahlVorlaufzeilen;
			$i = $letzteGueltige -1;
			while ($j) {
				$i = $zeilenSollgroesse-1 if $i < 0;
				$passt[$i] |= 2;
				$j--;
				$i--;
			}
		}
		# Weitere Zeile versuchen auszugeben. 
		#		Dies ist die aktuelle Zeile, falls $zeilenSollgroesse == 1 
		#		Sonst ist dies quasi $letzteGueltige + 1 falls diese belegt ist.
		$i = $letzteGueltige + 1;
		$i = 0 if $i >= $zeilenSollgroesse;
		if ( $i == $ersteGueltige ) {
			zeileAusgeben($dateiname, $zeilennr[$i], $bytePos[$i], $zeilen[$i], $passt[$i]) if !$nurDateinamenAusgeben && $passt[$i] & 2 && ! $nurZaehlen;
			if (1 == $zeilenSollgroesse) {
				$ersteGueltige = $letzteGueltige = -1;
			} else {
				$ersteGueltige++;
				$ersteGueltige = 0 if $ersteGueltige >= $zeilenSollgroesse;
			}
		}
		if ( $verbose ) {
			# Inhalt der zeilenbezogenen Arrays ausgeben:
			if (-1 == $ersteGueltige) {
				print "Keine Zeilen gespeichert\n";
			} else {
				print "Gespeicherte Zeilen in $dateiname [$ersteGueltige, $letzteGueltige]: (Zeilennr, Byte, paßt, Inhalt)\n";
				$i = $ersteGueltige;
				$j = $letzteGueltige - $i + 1;
				$j = $zeilenSollgroesse - $ersteGueltige + $letzteGueltige + 1 if $ersteGueltige > $letzteGueltige;
				while ($j--) {
					printf "%2d %5d %5d %d %s\n", $i, $zeilennr[$i], $bytePos[$i], $passt[$i], $zeilen[$i];
					$i++;
					$i = 0 if $i >= $zeilenSollgroesse;
				}
			}
		}
	}
	close IH;
	if ( $inDateiGefunden ) {
		if ($lGesetzt) {
			print "$dateiname\n";
		} else {
			# jetzt alle noch auszugebenden Zeilen ausgeben
			if ( $zeilenSollgroesse > 1 ) {
				$i = $ersteGueltige;
				$j = $letzteGueltige - $i + 1;
				$j = $zeilenSollgroesse - $ersteGueltige + $letzteGueltige + 1 if $ersteGueltige > $letzteGueltige;
				while ( $j-- ) {
					zeileAusgeben($dateiname, $zeilennr[$i], $bytePos[$i], $zeilen[$i], $passt[$i]) if $passt[$i] & 2 && ! $nurZaehlen;
					$i++;
					$i = 0 if $i >= $zeilenSollgroesse;
				}
			}
			$gesamtGefunden += $inDateiGefunden;
			print "$dateiname: $inDateiGefunden\n" if ( $nurZaehlen && $dateinamenAusgeben && $inDateiGefunden );
		}
	} elsif ( $LGesetzt ) {
		print "$dateiname\n";
	}
}	
print "Insgesamt gefundene Zeilen: $gesamtGefunden\n" if ( $nurZaehlen && ! $nurDateinamenAusgeben );
print "Noch zu implementierende Optionen: L, l, w\n" if $verbose;
