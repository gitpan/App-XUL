package App::XUL;

use 5.010000;
use strict;
use warnings;
use Directory::Scratch::Structured qw(create_structured_tree);
use File::Copy::Recursive qw(fcopy dircopy);
#use Data::Dumper;
use Data::Dumper::Concise;
use App::XUL::XML;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(AUTOLOAD);

our $VERSION = '0.03';
our $AUTOLOAD;

our $Singleton;

################################################################################

sub AUTOLOAD
{
	#print "auto1\n";
	$App::XUL::XML::AUTOLOAD = $AUTOLOAD;
	return App::XUL::XML::AUTOLOAD(@_);
}

################################################################################

sub new
{
  my ($class, @args) = @_;
  my $self = bless {}, $class;
  $Singleton = $self;
  return $self->init(@args);
}

sub init
{
  my ($self, %opts) = @_;
  $self->{'name'} = $opts{'name'} || do { die "Error: no app name given - new(name => <string>)\n" };
	$self->{'windows'} = [];
	$self->{'bindings'} = {};
  return $self
}

sub bind
{
	my ($id, $event, $coderef) = @_;
	$Singleton->{'bindings'}->{$id.':'.$event} = $coderef;
	return $Singleton;
}

sub add
{
	my ($self, $window_xml) = @_;
	die "Error: add() only accepts a single window tag as first argument\n"
		if $window_xml !~ /^<window/;
	push @{$self->{'windows'}}, $window_xml;
	return $self;
}

sub bundle
{
  my ($self, %opts) = @_;
  
  my $os = $opts{'os'} || die "Error: no os given - bundle(os => <string>)\n";
  my $path = $opts{'path'} || die "Error: no path given - bundle(path => <string>)\n";
  my $utilspath = $opts{'utilspath'} || die "Error: no utils path given - bundle(utilspath => <string>)\n";
  $self->{'debug'} = $opts{'debug'} || 0;
  
	#print Dumper($self);
	#exit;
	
	if ($os eq 'macosx') {
		my $name = $self->{'name'};

  	my $tmpdir = create_structured_tree(
			$name.'.app' => {
				'Contents' => {
					'Info.plist' => [$self->_get_file_maxosx_infoplist()],
					'Frameworks' => {
						#'XUL.framework' => {},
					},
					'MacOS' => {
						'start.pl' => [$self->_get_file_macosx_startpl()],
					},
					'Resources' => {
						'chrome.manifest' => ['manifest chrome/chrome.manifest'."\n"],
						'application.ini' => [$self->_get_file_macosx_appini()],
						#'MyApp.icns' => [],
						'chrome' => {
							# for older XUL.framework's we need the chrome.manifest here!
							'chrome.manifest' => [$self->_get_file_macosx_chromemanifest()],
						  'content' => {
							  #'AppXUL.js' => [],
							  #'AppXULServer.js' => [],
							  $self->_get_file_macosx_xulfiles(),
							  #'main.xul' => [$self->_get_file_macosx_mainxul()],
							},
						},
						'defaults' => {
							'preferences' => {
								'prefs.js' => [$self->_get_file_macosx_prefs()],
							},
						},
						'perl' => {
							'server' => {
								#'server.pl' => [$self->_get_file_macosx_serverpl()],
							},
							'modules' => {
								'Eventhandlers.pm' => [$self->_get_file_macosx_eventhandlers()],
								'App' => {
									'XUL' => {
										#'XML' => [],
										#'Object' => [],
									},
								},
							},
						},
						'extensions' => {},
						'updates' => {
							'0' => {},
						},
					},
				}
			}
		);
		
		# copy misc files into tmpdir
		die "Error: no XUL.framework found in /Library/Frameworks - please install XUL framework from mozilla.org\n"
			unless -d '/Library/Frameworks/XUL.framework';
		dircopy('/Library/Frameworks/XUL.framework', 
			$tmpdir->base().'/'.$name.'.app/Contents/Frameworks/XUL.framework');
			
		fcopy($utilspath.'/Appicon.icns',
			$tmpdir->base().'/'.$name.'.app/Contents/Resources/'.$name.'.icns');

		fcopy($utilspath.'/AppXUL.js', 
			$tmpdir->base().'/'.$name.'.app/Contents/Resources/chrome/content/AppXUL.js');

		#fcopy('../../misc/AppXULServer.js', 
		#	$tmpdir->base().'/'.$name.'.app/Contents/Resources/chrome/content/AppXULServer.js');

		fcopy($utilspath.'/server.pl', 
			$tmpdir->base().'/'.$name.'.app/Contents/Resources/perl/server/server.pl');

		fcopy($utilspath.'/../lib/App/XUL/XML.pm',
			$tmpdir->base().'/'.$name.'.app/Contents/Resources/perl/modules/App/XUL/XML.pm');

		fcopy($utilspath.'/../lib/App/XUL/Object.pm', 
			$tmpdir->base().'/'.$name.'.app/Contents/Resources/perl/modules/App/XUL/Object.pm');

		# chmod certain files
		chmod(0755, $tmpdir->base().'/'.$name.'.app/Contents/MacOS/start.pl');

		# move tmpdir to final destination		
		rename($tmpdir->base().'/'.$name.'.app', $path);
	}
	else {
		die "Error: os '$os' not implemented yet\n";
	}
}

################################################################################

sub _get_file_macosx_eventhandlers
{
	my ($self) = @_;
	my $eventhandlers = '';
	foreach my $name (keys %{$self->{'bindings'}}) {
		$eventhandlers .= "'".$name."' => \n".Dumper($self->{'bindings'}->{$name}).",\n";
	}
	return
		'package Eventhandlers;'."\n".
		'use App::XUL::XML;'."\n".
		'$App::XUL::XML::RunInsideServer = 1;'."\n".
		'our $AUTOLOAD;'."\n".
		'sub AUTOLOAD {'."\n".
		'	$App::XUL::XML::AUTOLOAD = $AUTOLOAD;'."\n".
		'	return App::XUL::XML::AUTOLOAD(@_);'."\n".
		'}'."\n".
		'sub get {'."\n".
		'	return {'."\n".
				$eventhandlers.		
		'	};'."\n".
		'}'."\n".
		'1;'."\n";
}

sub _get_file_macosx_prefs
{
	my ($self) = @_;
	return <<EOFSRC
pref("toolkit.defaultChromeURI", "chrome://$self->{'name'}/content/main.xul");

/* debugging prefs */
pref("browser.dom.window.dump.enabled", true);
pref("javascript.options.showInConsole", true);
pref("javascript.options.strict", true);
pref("nglayout.debug.disable_xul_cache", true);
pref("nglayout.debug.disable_xul_fastload", true);
EOFSRC
}

sub _get_file_macosx_xulfiles
{
	my ($self) = @_;
	my @files = ();
	my $w = 0;
	foreach my $window_xml (@{$self->{'windows'}}) {
		my $xml = 
			'<?xml version="1.0"?>'."\n".
			'<?xml-stylesheet href="chrome://global/skin/" type="text/css"?>'."\n".
			$window_xml;
		push @files, ($w == 0 ? 'main' : 'sub'.$w).'.xul', [$xml];
		$w++;
	}
	return @files;
#	return
#		'<?xml version="1.0"?>'."\n".
#		'<?xml-stylesheet href="chrome://global/skin/" type="text/css"?>'."\n".
#		$self->{'xml'};
#<window id="mw" title="$self->{'name'}" width="800" height="200"
#     xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul"
#     xmlns:html="http://www.w3.org/1999/xhtml">
#  <script src="AppXUL.js"/>
#  ...
#</window>
}

sub _get_file_macosx_chromemanifest
{
	my ($self) = @_;
	return 'content '.$self->{'name'}.' file:content/'."\n";
}

sub _get_file_macosx_appini
{
	my ($self) = @_;
	return <<EOFSRC
[App]
Version=1.0
Vendor=Me
Name=$self->{'name'}
BuildID=myid
ID={generated id}

[Gecko]
MinVersion=1.8
MaxVersion=2.*
EOFSRC
}

sub _get_file_macosx_startpl
{
	my ($self) = @_;
	return 
		'#!/usr/bin/perl -w'."\n".
		q{use strict;
		use Cwd 'abs_path';		
		my $path = abs_path($0);
			 $path =~ s/\/MacOS\/[^\/]+//;
		system(
			'"'.$path."/Resources/perl/server/server.pl".'" '.
			'"'.$path."/Resources/perl/modules/".'" 3000 &'
		);
		exec(
			$path."/Frameworks/XUL.framework/xulrunner-bin", 
			"-app", $path."/Resources/application.ini",}.
			($self->{'debug'} ? '"-jsconsole"' : '').
		');'."\n";
}

sub _get_file_maxosx_infoplist
{
	my ($self) = @_;
	return <<EOFSRC
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>start.pl</string>
	<key>CFBundleGetInfoString</key>
	<string>XULExplorer 1.0a1pre, © 2007-2008 Contributors</string>
	<key>CFBundleIconFile</key>
	<string>$self->{'name'}</string>
	<key>CFBundleIdentifier</key>
	<string>org.mozilla.mccoy</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$self->{'name'}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0a1pre</string>
	<key>CFBundleSignature</key>
	<string>MOZB</string>
	<key>CFBundleVersion</key>
	<string>1.0a1pre</string>
	<key>NSAppleScriptEnabled</key>
	<true/>
</dict>
</plist>
EOFSRC
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

App::XUL - Perl extension for creating deployable platform-independent
standalone desktop applications based on XUL and XULRunner.

=for html <span style="color:red">WARNING: PRE-ALPHA - DON'T USE FOR PRODUCTION!</span>

=head1 SYNOPSIS

  use App::XUL;
  my $app = App::XUL->new(name => 'MyApp');
  
  $app->add(
    Window(id => 'main',
      Div(id => 'container', 'style' => 'background:black', 
        Button(label => 'click', oncommand => sub {
          ID('container')->style('background:red');
        }),
      );
    )
  );
  
  $app->bundle(path => '/path/to/myapp.app', os => 'macosx');  

XUL (+ XULRunner) makes it easy to create applications based
on XML, CSS and JavaScript. App::XUL tries to simplify this
even more by exchanging XML and JavaScript with Perl and
providing an easy way to create deployable applications for the
platforms XULRunner exists for.

=head1 WHY XUL/XULRUNNER

XUL provides a set of powerful user widgets that look good
and work as expected. They can be created with minimal effort
and their appearance can be manipulated using CSS.

XUL is based on B<web technologies like XML, CSS and JavaScript>.
So anyone who is able to use these is able to create cool
desktop applications.

Here is the homepage of the L<XUL|https://developer.mozilla.org/En/XUL>
and L<XULRunner|https://developer.mozilla.org/en/xulrunner> projects at Mozilla.

An example of a XUL based application:

=begin html

<img src="data:image/jpg;base64,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
cqUSoXw6bGkzaR2WGQ7vVkrb7jnV+YKyVmX0B/Ow+vYJkBzYqGAvbYoS8dmXAjDfsC9Kapj3s23+
ugtVMTsz+XyFhO9O4zqZhjTXZC4TT7ziG3JfdiLcPJaUopQ4pCk2UEkkcNR1xTe0ZyrDmq7pmCDL
98NzZsNvMOkOx4S4aJhEh6a1ISHFhCRsVAYgVKCUlCjiVoSDrrdUqeWDKSa6eonf3s3BYYYfczB0
JkpdWyhK5y3SmOoJexNJu4nZlQx4kjDw1m8VUz0xzlprONz3sxay5iY69KeSlTYbdlrbO0b2yAXk
ktBSmu7CSq5Tptpq227CQrHrLGZwIQEVtO1KHZLaHUKedWlSSTcEKUa4cbDpxaXRWppZvDqdDvUu
GclvJmjUHe5zJY6IkWO1EjSsbsGfPW4p915CheKtCWwkMj5Wu/YrzqeCbo59BWONOrlO3VvuMkne
ds9RlZ3m+etTM6EHKbMxc0h5NBSkRVC8kMqU+C68lRWQ93KF2SLi+kKq0cE3RpegrW9eZTt2eYPf
MX2nZRPOzVh79e78zZEF9pKugtSS/MDjClKXASTJxRmnVPt2La7FTYSbaNYuXBN0qTaw+TPrhadq
2kW+Y6apdTnNoy6C1nWaOQcmE9G6TrT6psKM1GkvMAuty30tFSSh4pSpIVqWRpIvovT4HukpXFa3
pepvWKd+xWm7zspks5dnO7s3eVW7/UymJjSbyQ6/HC21bJLp+hD22WgYgnaoQUFXDRcD3RzFCs2v
z2c5Hv2MomrPyG5meUZbFipkR2A08h5jA4kquMTyEnh4QSK5MLhO7YdSqpoipbX5zNe+YtSh1WMs
bRffHt16B1w2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2
i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++P
boA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2
i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++P
boA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2i++PboA2
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
" alt="Image"/>

=end html

=head1 DESCRIPTION

=head2 new() - Creating an application

The constructor new() is used to create a new application

  my $app = App::XUL->new(name => 'MyApp');

=head3 Options

=head4 name => I<string>

The name of the application. Later also used as the application executable's name.

=head2 add() - Add a window to an application
 
add() adds a window to the XUL application. The XML for the window tag
and its contained tags is created using Perl functions. The names of
the Perl functions used to create the XML tags corresponds to the
tagnames, just the first letter is uppercase:
 
  $app->add(
    Window(id => 'main',
      Div(id => 'container', 'style' => 'background:black', 
        Button(label => 'click', oncommand => sub {
          ID('container')->style('background:red');
        }),
      );
    )
  );

Keep in mind, that add will fail if the added tag is NOT a window tag.
In XUL the root is always a window tag.

The first window beeing added is considered the main window and shown
on startup.

=head2 bundle() - Creating a deployable executable

  $app->bundle(path => '/path/to/myapp.app', os => 'macosx');  

This will create a complete standalone XUL application containing all XML code.

Some general information about
L<XUL application deployment|https://wiki.mozilla.org/XUL:XUL_Application_Packaging>.

=head3 Options

=head4 path => I<string>

=head4 os => I<string>

The systems currently supported are:

=over 1

=item macosx (Mac OS X)

L<Apple Documentation|http://developer.apple.com/library/mac/#documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html#//apple_ref/doc/uid/10000123i-CH101-SW1>

=item win (Windows)

coming soon

=item deb or rpm (Ubuntu Linux)

tbd. Either a *.deb or *.rpm Paket.

=back

=head4 debug => I<1/0>

If debug is set to 1, a jsconsole is started together with the application
which can be used to debugging messages. The default is debug = 0, so no
jsconsole is started.

=head2 Creating interface components

=head2 Handling events

Events can be handled by attaching an event handler to
an interface component. Event handlers can either be written
in Perl or in JavaScript.

Here is an example of a Perl event handler that reacts on
the mouse click of a button:

  Button(label => 'click', oncommand => sub {
    # access environment and evtl. change it
    # ...
  });

Here is a similar JavaScript event handler:

  Button(id => 'btn', label => 'click', oncommand => <<EOFJS);
    // here is some js code
    $('btn').update('Alrighty!');
  EOFJS

JavaScript event handlers are executed faster than the Perl ones,
due to the architecture (see below).


=head2 Changing the environment from Perl

This refers to all activities within Perl event handlers that
change the DOM of the XUL application. An example is the
addition of another window, the insertion or update of a button
label or the deletion of a style attribute etc.

Some things are important here:

=over 1

=item Changes happen on the server side first and are
  transferred to the client side (the XUL application)
  when the event handler terminates.

=item To manually transfer the latest changes to the client side
  use the PUSH() function.

=back

=head4 Get (XML) element

The first step of changing the DOM is to get an element on which
the changes are applied. The ID() function is used for that:

  my $elem = ID('main');

The ID() function only works WHILE the application is running.
Any changes to the object returned by the ID() function are transferred
immedietly (asynchronous) to the XUL application/client.

=head4 Get child (XML) elements

  my $child1 = ID('main')->child(0);
  my $numchildren = ID('main')->numchildren();

=head4 Create/insert/append (XML) elements

  my $e = Div(id => 'container', 'style' => 'background:black', 
            Button(label => 'click'));
  ID('main')->insert($e, 'end'); # end|start|...

=head4 Edit (XML) element

  ID('container')->style('background:red')->content(Span('Hello!'));

=head4 Delete/remove (XML) element

  my $e = ID('container')->remove();

=head4 Call event handler on (XML) element

  ID('container')->click();

=head4 Register event handler on (XML) element

  ID('container')->oncommand(sub {
    # do stuff here
    # ...
  });

=head4 Un-register event handler on (XML) element

  ID('container')->oncommand(undef);
            

=head2 EXPORT

None by default.

=head1 INTERNALS

This chapter is meant for informational purposes. Sometimes it is nessessary
to know how things are implemented to decide, for example, if you should
use a Perl or a JavaScript event handler etc.

App::XUL is client-server based. The client is the instance of
XULRunner running and the server is a pure Perl based webserver
that reacts on the events that are triggered by the XUL interface.

=head3 Event handling

Essentially all events are dispatched from XUL as Ajax calls to the
Perl webserver which handles the event, makes changes to the DOM etc.
The changes are then transferred back to the XUL app where they
are applied.

Here is a rough workflow for event handling:

=over 1

=item 1. Client registers an event (e.g. "mouseover", "click", "idle" etc.)

=item 2. Client sends message to server (incl. parameters and environment)

=item 3. Server calls appropriate Perl event handler subroutine
  (which may manipulate the environment)

=item 4. Server sends the environment changes to the client as response

=item 5. Client integrates environment changes

=back    

=head3 Communication protocol

The communication between XUL and server is based on a simple
JSON based protocol. The following syntax definition tries to
define the protocol. Everything in curly brackets is a JSON object,
strings are quoted and non-terminals are written within "<",">" brackets.
The pipe symbol ("|") means "OR".

  <CLIENT-REQUEST> := <EVENT>
  
  <SERVER-RESPONSE> := <ACTION>

  <SERVER-REQUEST> := <ACTION>

  <CLIENT-RESPONSE> := <STRING>
  
  <EVENT> := {
    event: <EVENTNAME>,
    id: <ID>
  }

    <EVENTNAME> := 
      "abort" |
      "blur" |
      "change" |
      "click" |
      "dblclick" |
      "dragdrop" |
      "error" |
      "focus" |
      "keydown" |
      "keypress" |
      "keyup" |
      "load" |
      "mousedown" |
      "mousemove" |
      "mouseout" |
      "mouseover" |
      "mouseup" |
      "move" |
      "reset" |
      "resize" |
      "select" |
      "submit" |
      "unload"

  <ACTION> := 
    <UPDATE> | 
    <REMOVE> | 
    <CREATE> | 
    <QUIT> |
    <CHILD> | 
    <NUMCHILDREN> |
    <INSERT> |
    <TRIGGER> |
    <REGISTER> |
    <UNREGISTER> |
    <SETATTR> |
    <GETATTR>
    
    <UPDATE> := {
      action: "update",
      id: <ID>,
      attributes: <ATTRIBUTES>,
      subactions: [ <ACTION>, ... ]
    }

      <ATTRIBUTES> := {<NAME>: <STRING>, ...}
  
    <REMOVE> := {
      action: "remove",
      id: <ID>,
      subactions: [ <ACTION>, ... ]
    }

    <CREATE> := {
      action: "create",
      parent: <ID>,
      attributes: <ATTRIBUTES>,
      content: <STRING>,
      subactions: [ <ACTION>, ... ]
    }
    
    <QUIT> := {
      action: "quit"
    }

    <CHILD> := {
      action: "child",
      id: <ID>,
      number: <NUMBER>
    }
    
    <NUMCHILDREN> := {
      action: "numchildren",
      id: <ID>
    }
    
    <INSERT> := {
      action: "insert",
      id: <ID>,
      position: <POSITION>,
      content: <STRING>
    }
    
    <TRIGGER> := {
      action: "trigger",
      id: <ID>,
      name: <STRING>
    }
    
    <REGISTER> := {
      action: "register",
      id: <ID>,
      name: <STRING>,
      callback: <STRING>
    }
    
    <UNREGISTER> := {
      action: "unregister",
      id: <ID>,
      name: <STRING>
    }
    
    <SETATTR> := {
      action: "setattr",
      id: <ID>,
      name: <STRING>,
      value: <STRING>
    }
    
    <GETATTR> := {
      action: "getattr",
      id: <ID>,
      name: <STRING>
    }

Here are some examples of client requests:

  {event:"click", id:"btn"}

Here are some examples of server responses:

  {action:"update", id:"btn", attributes:{label:"Alrighty!"}}

  {action:"remove", id:"btn"}

  {action:"create", parent:"main", content:"<button .../>"}

=head3 Application bundling for Mac OS X

Mac applications are simply directories whose names end with ".app"
and have a certain structure and demand certain files to exist.

This is the structure of a XUL application wrapped inside a Mac application
as created by App::XUL (files are blue, directories are black):

=begin html

<pre>
  MyApp.app/
    Contents/
      <span style="color:blue;font-weight:bold">Info.plist</span>
      Frameworks/
        XUL.framework/
          <i>The XUL Mac framework</i>
      MacOS
        <span style="color:blue;font-weight:bold">start.pl</span> (Perl-Script)
      Resources
        <span style="color:blue;font-weight:bold">application.ini</span>
        <span style="color:blue;font-weight:bold">MyApp.icns</span>
        chrome/
          <span style="color:blue;font-weight:bold">chrome.manifest</span>
          content/
            <span style="color:blue;font-weight:bold">AppXUL.js</span>
            <span style="color:blue;font-weight:bold">myapp.xul</span>
        defaults/
          preferences/
            <span style="color:blue;font-weight:bold">prefs.js</span>
        perl/
          server/
            <span style="color:blue;font-weight:bold">server.pl</span>
          modules/
            <i>All Perl modules the server depends on</i>
        extensions/
        updates/
          0/
</pre>

=end html

The various files have specific functions. When the MyApp.app is
clicked, the B<start.pl> program is executed which then starts the
server and the client:

=over 1

=item Info.plist

Required by Mac OS X. This is the place where certain basic information
about the application is read by Mac OS X, before anything else is done.
For example, here the start.pl program is defined as the entry point
of the application.

=item start.pl

First program to be executed. Starts server and client.

=item application.ini

Setups the XUL application. Defines which *.xul files to load,
name of application etc.

=item AppXUL.js

Defines all Javascript functions used by App::XUL to manage the
communication with the server.

=item myapp.xul

Defines the basic UI for the XUL application.

=item prefs.js

Sets some preferences for the XUL application.

=item server.pl

This starts the server.

=back

=head3 Application bundling for Windows

tbd. Use L<NSIS|http://nsis.sourceforge.net/Main_Page> or
L<InstallJammer|http://www.installjammer.com/>.

=head3 Application bundling as DEB package

tbd. See L<Link|http://www.webupd8.org/2010/01/how-to-create-deb-package-ubuntu-debian.html>.

=head3 Application bundling as RPM package

tbd.

=head1 ROADMAP

One thing on the todo list is to create a full-duplex connection
between client and server so that the client can react on
server events directly. This may be implemented using the HTML5
WebSocket protocol. For now all communication is iniciated from
the client using AJAX calls.

=head1 SEE ALSO

This module actually stands a bit on its own with its approach.
XUL modules exist though - XUL::Gui, XUL::Node and a few more.

=head1 AUTHOR

Tom Kirchner, E<lt>tom@tomkirchner.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Tom Kirchner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
