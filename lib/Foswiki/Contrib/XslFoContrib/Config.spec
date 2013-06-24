# ---+ Extensions
# ---++ XslFoContrib
# **PERL H** 
# This setting is required to register the fop service
$Foswiki::cfg{SwitchBoard}{fop} = {
  package  => 'Foswiki::Contrib::XslFoContrib',
  function => 'fop',
  context  => { fop => 1 },
};

# **COMMAND**
# fop commandline tool to process FO directly
$Foswiki::cfg{XslFoContrib}{FopFoCommand}  = '$Foswiki::cfg{ToolsDir}/fop/fop -c $Foswiki::cfg{ToolsDir}/fop/conf/fop.conf %FOFILE|F% -%FORMAT|S% -';

# **COMMAND**
# fop commandline tool to transform an input xml using xsl 
$Foswiki::cfg{XslFoContrib}{FopXmlCommand} = '$Foswiki::cfg{ToolsDir}/fop/fop -c $Foswiki::cfg{ToolsDir}/fop/conf/fop.conf -xml %XMLFILE|F% -xsl %XSLFILE% -%FORMAT|S% -';

1;
