# See bottom of file for default license and copyright information
package Foswiki::Contrib::XslFoContrib;

use strict;
use warnings;

our $VERSION = '1.00';
our $RELEASE = '1.00';
our $SHORTDESCRIPTION = 'FOP print formatter';

use Foswiki ();
use Foswiki::UI ();
use Foswiki::Func ();
use File::Temp ();

use constant DEBUG => 0;

sub writeDebug {
  print STDERR "- XslFoContrib - " . $_[0] . "\n" if DEBUG;
}

sub fop {
  my ($session) = @_;

  writeDebug("called fop");

  my $request = $session->{request};
  my $response = $session->{response};

  my $web = $session->{webName};
  my $topic = $session->{topicName};
  my $section = $request->param("section");
  my $format = $request->param("format") || 'pdf';
  my $xslWebTopic = $request->param("xsltopic");
  my $xslSection = $request->param("xslsection");
  my $xslAttachment = $request->param("xslattachment");
  my $fileName = $request->param("filename") || $topic.".".$format;
  $fileName .= ".".$format unless $fileName =~ /\.(pdf|rtf|txt|html|ps|afp|tiff|png|pcl)$/; # TODO: what else?

  Foswiki::UI::checkTopicExists($session, $web, $topic, 'view');

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  Foswiki::UI::checkAccess($session, 'VIEW', $meta);

  writeDebug("topic=$web.$topic");

  # get content
  my $content = '%TEXT%';
  my $xsl;
  my $template = $request->param('template');
  if ($template) {
    Foswiki::Func::loadTemplate($template);
    $content = Foswiki::Func::expandTemplate("xml");
    $xsl = Foswiki::Func::expandTemplate("xsl");
  }

  if (defined $section) {
    writeDebug("section=$section");
    $text = extractSection($text, $section) || '';
  } else {
    $text =~ s/.*%STARTINCLUDE%\s*//gs;
    $text =~ s/\s*%STOPINCLUDE%.*//gs;
  }

  $content =~ s/%TEXT%/$text/g;
  $content = Foswiki::Func::expandCommonVariables($content, $topic, $web, $meta);
  $content =~ s/(<fo:external\-graphic[^>]+src=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
  $content =~ s/(<xsl:include[^>]+href=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
  $content =~ s/<\/?noautolink>|<nop>|<\/?literal>//g;
  #writeDebug("content=$content");

  my $xslWeb = $web;
  my $xslTopic = $topic;
  my $xslMeta = $meta;

  if (defined $xslWebTopic) {
    ($xslWeb, $xslTopic) = Foswiki::Func::normalizeWebTopicName($web, $xslWebTopic);
    writeDebug("xsl web=$xslWeb, topic=$xslTopic");
  }

  if ($xslAttachment) {
    writeDebug("xslAttachment=$xslAttachment");
    $xsl = Foswiki::Func::readAttachment($xslWeb, $xslTopic, $xslAttachment);
  } else {
    if (defined $xslWebTopic || defined $xslSection) {
      ($xslMeta, $xsl) = Foswiki::Func::readTopic($xslWeb, $xslTopic);
    }
    if (defined $xslSection) {
      writeDebug("xslSection=$xslSection");
      $xsl = extractSection($xsl, $xslSection) || '';
    } else {
      if (defined $xsl) {
        $xsl =~ s/.*%STARTINCLUDE%\s*//gs;
        $xsl =~ s/\s*%STOPINCLUDE%.*//gs;
      }
    }
  }

  my $stdout;
  my $exit;
  my $stderr;

  if (defined $xsl) {
    # xsl mode
    writeDebug("xsl mode, xslTopic=$xslTopic, xslWeb=$xslWeb");

    Foswiki::Func::pushTopicContext($xslWeb, $xslTopic) if ($web ne $xslWeb || $topic ne $xslTopic);

    $xsl = Foswiki::Func::expandCommonVariables($xsl, $xslTopic, $xslWeb, $xslMeta);
    $xsl =~ s/(<fo:external\-graphic[^>]+src=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
    $xsl =~ s/(<xsl:include[^>]+href=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
    $xsl =~ s/<\/?noautolink>|<nop>|<\/?literal>//g;

    #writeDebug("xsl=$xsl");

    Foswiki::Func::popTopicContext() if ($web ne $xslWeb || $topic ne $xslTopic);;

    my $xmlFile = new File::Temp(SUFFIX => '.xml', UNLINK => (DEBUG ? 0 : 1));
    writeDebug("xmlFile=" . $xmlFile->filename);

    print $xmlFile $content;

    my $xslFile = new File::Temp(SUFFIX => '.xsl', UNLINK => (DEBUG ? 0 : 1));
    writeDebug("xslFile=" . $xslFile->filename);

    print $xslFile $xsl;

    my $fopCmd = $Foswiki::cfg{XslFoContrib}{FopXmlCommand}
      || "/usr/bin/fop -xml %XMLFILE|F% -xsl %XSLFILE% -%FORMAT|S% -";

    writeDebug("fopCmd=$fopCmd");

    ($stdout, $exit, $stderr) = Foswiki::Sandbox::sysCommand(
      undef, $fopCmd,
      XMLFILE => $xmlFile->filename,
      XSLFILE => $xslFile->filename,
      FORMAT => $format,
    );

  } else {
    # fo mode
    writeDebug("fo mode");

    my $foFile = new File::Temp(SUFFIX => '.fo', UNLINK => (DEBUG ? 0 : 1));
    writeDebug("foFile=" . $foFile->filename);

    print $foFile $content;

    my $fopCmd = $Foswiki::cfg{XslFoContrib}{FopFoCommand}
      || "/usr/bin/fop %FOFILE|F% -%FORMAT|S% - ";

    writeDebug("fopCmd=$fopCmd");

    ($stdout, $exit, $stderr) = Foswiki::Sandbox::sysCommand(
      undef, $fopCmd,
      FOFILE => $foFile->filename,
      FORMAT => $format,
    );
  }

#  writeDebug("stderr=$stderr, exit=$exit");
#  if ($stderr) {
#    print STDERR "- XslFoContrib - $stderr\n";
#  }

  my $mimeType = formatToMimeType($format);
  writeDebug("format=$format, mimeType=$mimeType");

  if ($exit) {
    my $line = 1;
    $content =~ s/^/sprintf("%03d", $line++)."  "/gem;
    $session->writeCompletePage("Error: " . $stderr . "\n" . $content .(defined $xsl?"\n'$xsl'":""), "txt", "text/plain");
  } else {
    $response->header(
      -status => 200,
      -type => $mimeType,
      -content_disposition => "inline; filename=\"$fileName\"",
    );
    $response->print($stdout);
  }

  return;
}

my $types;    # cache content of MimeTypesFileName

sub formatToMimeType {
  my $format = shift;

  #return "application/msword" if $format eq 'rtf';

  my $mimeType = 'application/octet-stream';
  if ($format) {
    $types = Foswiki::Func::readFile($Foswiki::cfg{MimeTypesFileName}) unless defined $types;

    if ($types =~ /^([^#]\S*).*?\s$format(?:\s|$)/im) {
      $mimeType = $1;
    }
  }

  return $mimeType;
}

sub extractSection {
  my ($text, $name) = @_;

  # SMELL: no Func api for parseSections
  my ($ntext, $sections) = Foswiki::parseSections($text);

  for my $s (@$sections) {
    if ($s->{type} eq 'section' && $s->{name} eq $name) {
      my $section = substr($ntext, $s->{start}, $s->{end} - $s->{start});
      $section =~ s/^\s*//gs;
      $section =~ s/\s*$//gs;
      return $section;
    }
  }

  return;
}

sub toFileUrl {
  my $url = shift;

  my $fileUrl = $url;

  if ($fileUrl =~ /^(?:$Foswiki::cfg{DefaultUrlHost})?$Foswiki::cfg{PubUrlPath}(.*)$/) {
    $fileUrl = $1;
    $fileUrl =~ s/\?.*$//;
    if ($fileUrl =~ /^\/(.*)\/([^\/]+)\/[^\/]+$/) {
      my $web = $1;
      my $topic = $2;
      my $wikiName = Foswiki::Func::getWikiName();
      writeDebug("checking access for $wikiName on $web.$topic");
      return '' unless Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web);
    }
    $fileUrl = "file://".$Foswiki::cfg{PubDir}.$fileUrl;
  } else {
    writeDebug("url=$url does not point to the local server");
  }

  writeDebug("url=$url, fileUrl=$fileUrl");
  return $fileUrl;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2013 Michael Daum http://michaeldaumconsulting.com

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
