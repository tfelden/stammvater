#!/usr/bin/perl -w
#
# Thomas Felden
#
#  Ließt alle Verzeichnisse ab dem angegebenen Pfad und speichert dort eine leere Datei .gitignore
#  falls diese dort nicht existiert.
 
use Encode;
use Encode::Guess;
use Getopt::Long;
use Data::Dumper;
use Devel::StackTrace;
use Devel::Size qw(size total_size);
use Felden;
use File::Basename;
use File::Spec;
use strict;

our $verbose = 0;
my $ausgabe = '';
my $startverzeichnis = '';
my $externesVerbose = 0;
my $hilfeAusgeben = 0;
my $gitignoreLoeschen = 0;
my $keineAktion = 0;            # 1 <=> es wird nichts gelöscht oder erzeugt
our @dateinamen = ();						# Diese Dateien in dieser Reihenfolge untersuchen
our $fehlerUnterdruecken = 0;		# 1 <=> Fehlermeldungen zu nicht lesbaren oder nicht existierenden Dateien werden unterdrückt
our $rekursiv = 1;							# 1 <=> auch alle Unterverzeichnisse durchsuchen. 0 sonst
our %verzeichnisinhalt = ();    # Schlüssel = Verzeichnisname; Wert = Liste der enthaltnen Dateien und Verzeichnisse ohne . und ..

Getopt::Long::Configure ("bundling");
GetOptions(
  'a=s' => \$ausgabe, 'ausgabe=s' => \$ausgabe,
  'g' => \$gitignoreLoeschen, 'gitignoreLoeschen' => \$gitignoreLoeschen,
  'h' => \$hilfeAusgeben, 'hilfe' => \$hilfeAusgeben, 
  'k' => \$keineAktion, 'keineAktion' => \$keineAktion,
  's=s' => \$startverzeichnis, 'startverzeichnis=s' => \$startverzeichnis,
  'v' => \$externesVerbose, 'verbose' => \$externesVerbose,
  );
$_ = "Erkannte Parameter: ";
$_ .= "-a $ausgabe " if $ausgabe ne '';
$_ .= "-g " if $gitignoreLoeschen;
$_ .= "-h " if $hilfeAusgeben;
$_ .= "-k " if $keineAktion;
$_ .= "-s $startverzeichnis " if $startverzeichnis ne '';
$_ .= "-v " if $externesVerbose;
$_ .= "Restliche Parameter = (" . join(', ', @ARGV) . ")" if -1 < $#ARGV;

$verbose |= $externesVerbose;
*AH = *STDOUT;
if ($ausgabe ne '') {
  open(AH, ">$ausgabe") or geheSterben("Konnte Datei $ausgabe nicht zum Schreiben öffnen: $!\n");
}
my $aufrufparameter = $_;
$_ .= "\n";
print $_ if $verbose;

beschreibeParameter("Hilfe angefordert") if $hilfeAusgeben;
beschreibeParameter("Das Startverzeichnis muss angegeben werden") if $startverzeichnis eq '';

# beschreibt einen fehlenden Parameter
sub beschreibeParameter {
  my ($fehler) = @_;
  print encode('cp850', "Achtung: $fehler!\n");
  print encode('cp850', <<Textende);
Durchsucht alle Verzeichnisse unterhalb des Startverzeichnisses.
Ohne entsprechende Parameter wird in jedem leeren Unterverzeichnis eine leere Datei .gitignore angelegt.

Parameter:
-a ausgabedatei, --ausgabe=ausgabedatei
    Schreibt die erzeugte Ausgabe in diese Datei.
-g, --gitignoreLoeschen
    Dateien mit dem Namen .gitignore werden in sonst leeren Verzeichnissen gelöscht 
-h, --hilfe
    Gibt die Hilfe aus und beendet das Programm.
-k, --keineAktion
    Statt eine Aktion auszuführen wird nur beschrieben was ausgeführt würde.
    Das Verzeichnissystem bleibt unverändert.
-s verzeichnis, --startverzeichnis=verzeichnis
    In diesem Verzeichnis startet die Suche nach leeren Verzeichnissen.
-v, --verbose
    Gibt weitere Informationen aus.
Textende
exit 0;
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
				print STDERR "Konnte Datei ($aufzuloesen) nicht lesen\n";
			}
		} elsif ( -d $aufzuloesen ) {
			if ($rekursiv) {
				if ( -r $aufzuloesen ) {
					# ist ein lesbares Verzeichnis
					if ( ! opendir DIR, $aufzuloesen ) {
						if ( 0 == $fehlerUnterdruecken ) {
							print STDERR "Konnte Verzeichnis ($aufzuloesen) nicht öffnen\n";
						}
					} else {
						@enthalten = grep !/^\.\.?\z/,readdir DIR;	# . und .. ignorieren
						closedir DIR;
						$verzeichnisinhalt{$aufzuloesen} = [];
						#print "\%verzeichnisinhalt\n", Dumper(\%verzeichnisinhalt);
						#print "\@enthalten\n", Dumper(\@enthalten);
						foreach $_ ( @enthalten ) {
						  push @{$verzeichnisinhalt{$aufzuloesen}}, $_;
						}
						#print "Verzeichnis $aufzuloesen lokal aufgelöst => \n" . join("\n",@enthalten) . "\n";
						@enthalten = map {File::Spec->catfile($aufzuloesen, $_)} @enthalten;
						#print "Verzeichnis $aufzuloesen sortiert aufgelöst => \n" . join("\n",@enthalten) . "\n";
						loeseGlobsAuf(@enthalten);
					}
				} elsif ( 0 == $fehlerUnterdruecken ) {
					print STDERR "Konnte Datei ($aufzuloesen) nicht lesen\n";
				}
			}
		} else {
			# hier versuchen dies als glob zu sehen
			@enthalten = glob($aufzuloesen);
			if ( $#enthalten > 0 ) {
				loeseGlobsAuf(sort @enthalten);
			} elsif ( $#enthalten == 0 && $aufzuloesen eq $enthalten[0] ) {
				print STDERR "Datei $aufzuloesen konnte nicht gefunden werden\n" if ! $fehlerUnterdruecken;
			} else {
				print STDERR "Konnte keine Datei zu $aufzuloesen finden\n" if ! $fehlerUnterdruecken;
			}
		}
	}
	return 1;
}

my @startverzeichnisse = ($startverzeichnis);
loeseGlobsAuf(@startverzeichnisse);
if ($verbose && $#dateinamen >= 0) {
	print "Dateien nach dem Auflösen:\n";
	foreach (@dateinamen) {
		print "  $_\n";
	}
	foreach $_ (sort keys %verzeichnisinhalt) {
	  my @enthalten = @{$verzeichnisinhalt{$_}};
	  if ($#enthalten >= 0) {
  	  print "Verzeichnis $_ enthält:\n";
  	  foreach my $name (sort @enthalten) {
  	    print "  $name\n";
  	  }
  	} else {
  	  print "Verzeichnis $_ ist leer\n";
  	}
	}
}


# jetzt in alle leeren Verzeichnisse eine leere Datei .gitignore einfügen
if ($gitignoreLoeschen) {
  my $datei;
	foreach $_ (sort keys %verzeichnisinhalt) {
	  my @enthalten = @{$verzeichnisinhalt{$_}};
	  if ($#enthalten == 0 and $enthalten[0] =~ /\.gitignore$/) {
  	  print "Aus Verzeichnis $_ .gitignore löschen\n" if $verbose;
  	  $datei = File::Spec->catfile($_, '.gitignore');
  	  if ($keineAktion) {
  	    print "Aus Verzeichnis $_ sollte .gitignore gelöscht werden\n";
  	  } else {
    	  unlink $datei;
    	}
  	}
	}
} else {
  my $datei;
	foreach $_ (sort keys %verzeichnisinhalt) {
	  my @enthalten = @{$verzeichnisinhalt{$_}};
	  if ($#enthalten < 0) {
  	  print "In Verzeichnis $_ .gitignore einfügen\n" if $verbose;
  	  $datei = File::Spec->catfile($_, '.gitignore');
  	  if ($keineAktion) {
  	    print "Datei $datei sollte erzeugt werden\n";
  	  } else {
      	open(FH,">$datei") or die "Konnte Datei $datei nicht zum Schreiben öffnen: $!\n";
      	print FH "\#* sorgt für das ignorieren von allen Dateien\n\# !.gitignore beachtet diese Datei\n*\n!.gitignore\n";
      	close FH;
      }
  	}
	}
}      
exit 0;
