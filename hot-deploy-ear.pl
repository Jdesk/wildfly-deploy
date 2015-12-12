#!/usr/bin/perl 
=head
# ##################################
# Module : deploy
#
# SYNOPSIS
# This script to deploy the Jenkins Artifacts to Wildfly.
#
# Copyright 2015 eGovernments Foundation
#
#  Log
#  By          	Date        	Change
#  Vasanth KG  	29/11/2015	    Initial Version
#
# #######################################
=cut

# Add template folder to PAR file
# PAR Packager : pp -a template -M Crypt::Blowfish -M JSON::backportPP -M Decrypt -M DateTime -M Email.pm -M Nexus.pm -M Wildfly.pm -M Common.pm --clean -o hot-deploy-ear hot-deploy-ear.pl
# Package name
package deploy;

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use LWP;
#use LWP::UserAgent::ProgressBar;
#use Term::ProgressBar;
use JSON;
use Getopt::Long;
use Cwd;
use utf8;
use Encode;
#use MIME::Base64;
use Cwd 'abs_path';
use File::Tee qw(tee);
use File::Basename;
use File::Path qw(make_path);
use Log::Log4perl qw(:easy);
use HTML::Template;
use Common;
use Nexus;
use Wildfly;
use Email;
use Decrypt;
use Data::Dumper qw(Dumper);
use Config::Properties;
#use XML::Simple;
use Net::SMTP::SSL;
use Net::Address::IP::Local;
use Crypt::CBC;
use MIME::Base64;

use constant TRUE => 0;
use constant FALSE => 1;


my ($environment, $buildnumber, $error_flag, $par_template_dir, $api_artiRelativePath, $api_artifilename);

## PAR TEMP path to get the Template path
my $DEBUG = FALSE;
if ( $DEBUG == FALSE )
{
	$par_template_dir = "$ENV{PAR_TEMP}/inc/template";
}
else
{
	$par_template_dir = $FindBin::Bin."/template";
}
#############################################

# Start
#my $DEPLOY_HOME = $ENV{'HOME'}."/devops";
my $DEPLOY_HOME = $FindBin::Bin;
my $DEPLOY_RUNTIME = $ENV{'HOME'}."/.deploy-runtime";
my $baseConfigFile = $DEPLOY_HOME."/configuration.properties";
my $jenkinsUserName = $ENV{'JENKINS_USERNAME'};
my $jenkinsToken = $ENV{'JENKINS_AUTH_URL_TOKEN'}; 


Log::Log4perl->easy_init($ERROR);
my $conf = q(	log4perl.logger      = DEBUG, Screen, File
    			log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
    			log4perl.appender.Screen.stderr = 1
    			log4perl.appender.Screen.mode   = append
    			log4perl.appender.Screen.layout = Log::Log4perl::Layout::PatternLayout
    			log4perl.appender.Screen.layout.ConversionPattern = %d %p - %m%n
    			log4perl.appender.File=Log::Log4perl::Appender::File
    			log4perl.appender.File.stderr = 1
    			log4perl.appender.File.filename=sub { Common::get_log_filename(); }
    			log4perl.appender.File.mode=append
    			log4perl.appender.File.layout=Log::Log4perl::Layout::PatternLayout
    			log4perl.appender.File.layout.ConversionPattern=%d %p - %m%n
    			);
Log::Log4perl::init(\$conf);
my $logger = get_logger();

Getopt::Long::GetOptions(
	   'environment|e=s' => \$environment,
	   'buildnumber|b=i' => \$buildnumber,
	   'config|c=s'  => \$baseConfigFile
	) or die "Usage: $0 -e <qa/uat/prod> -b <build-number>\n";

chomp $environment && chomp $buildnumber && chomp $baseConfigFile;
###### Validation
Common::usage( $logger, $environment, $buildnumber, $baseConfigFile );
Common::validateJenkinsVariable($logger,$jenkinsUserName,$jenkinsToken);

$logger->info("Initiating the Deployment on ".$environment." environment");

#create DEPLOY_RUNTIME folder
my $deploy_home_status = ( !-d $DEPLOY_RUNTIME ) ? (make_path( $DEPLOY_RUNTIME , { mode => 0755}) && "Created DEPLOY_RUNTIME folder") : "Already exists DEPLOY_RUNTIME folder.." ;
$logger->info("$deploy_home_status");
chdir ($DEPLOY_RUNTIME);
#########################################

#Read property files
open my $inputData, '<:utf8', $baseConfigFile or ($logger->error("Cannot open configuration file $baseConfigFile : No such file or directory.") and exit 1);
my $baseConfProperties = new Config::Properties();
$baseConfProperties->load($inputData);

my ($TENANT_NAME,$WILDFLY_USERNAME,$WILDFLY_PASSWORD,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$JENKINS_URL,
    $masterHostname,$sharedFolderPath,$wildfly_context,$NEXUS_HOME_URL,$NEXUS_PUBLIC_REPO,$NEXUS_GROUP_ID,
    $NEXUS_ARTIFACT_ID,$NEXUS_PACKAGE_TYPE,$NEXUS_VERSION,$digiSign_status,$slaveHostname) 
    = Common::parseConfigFile($DEPLOY_HOME, $baseConfProperties, $environment, $logger);

	# Get the local system's IP address that is "en route" to "the internet":
	my $hostAddress      = Net::Address::IP::Local->public;
	$hostAddress =~ s/\n//g;
	chomp $hostAddress;
	
	if ( $masterHostname ne $hostAddress )
	{
		$logger->fatal("Deploy script must run on master node ==> ".$masterHostname);
		$logger->error("Deployment request terminated.");
		Email::notify_deployment_failure($logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,"Deploy script must run on master node ==> ".$masterHostname,$buildnumber); 
		exit 1;
	}
	
# Notify about the deployment to team
$logger->info("Notify about the deployment to team.");
Email::notify_deployment_alert($logger, $TENANT_NAME, $par_template_dir, $environment, $baseConfigFile,$buildnumber,$JENKINS_URL); 

$logger->info("Found wildfly home ==> ".$WILDFLY_HOME);

# Check wildfly is booted or not
my $wildfly_host_list = $masterHostname.",".$slaveHostname;
my @wildfly_hosts = split (",", $wildfly_host_list);

foreach my $wildfly_host (@wildfly_hosts)
{
	$logger->info("Verifying wildfly management service on ".$wildfly_host);
	my $WILDFLY_SERVICE_STATUS = `curl -S -H "Content-Type: application/json" -d '{"operation":"read-attribute","name":"server-state","json.pretty":1}' --digest http://${WILDFLY_USERNAME}:${WILDFLY_PASSWORD}\@${wildfly_host}:$WILDFLY_MGMT_PORT/management/ --max-time 15 -s`;
	my $e;
	eval {
	  $e = decode_json($WILDFLY_SERVICE_STATUS);
	  $WILDFLY_SERVICE_STATUS = $e->{result};
	  1;
	};
	if ( $WILDFLY_SERVICE_STATUS ne "running")
	{
		$logger->warn("Notify deployment failure.");
		$logger->error("Terminating DEPLOYMENT request, as the wildfly management service is not running on '". $wildfly_host."' host");
		print "\n";
		Email::notify_deployment_failure($logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,"Wildfly management service is not running on '". $wildfly_host."' host",$buildnumber, $wildfly_host); 
		exit 1;
	}
}
#########################################
# Existing EAR backup
#Wildfly::backupEar($logger,$WILDFLY_HOME);

#########################################

# Jenkins job details
my $JOB_CONTENT = decode_json(Common::jenkinsAuthToken($logger, $TENANT_NAME, $par_template_dir, $baseConfigFile, $environment, $jenkinsUserName, $jenkinsToken, $JENKINS_URL, $buildnumber));

my $api_fullDisplayName = $JOB_CONTENT->{fullDisplayName};
my $api_jenkins_url = $JOB_CONTENT->{url};
my $api_buildid = $JOB_CONTENT->{id};
my ( $api_git_url, $SCM_DETAILS );

my %API_SCM_HASH;
foreach $SCM_DETAILS (@{( $JOB_CONTENT->{actions})})
{
	$API_SCM_HASH{'branchname'} = $_->{name} foreach @{($SCM_DETAILS->{lastBuiltRevision}->{branch})};
 	$API_SCM_HASH{'SHA1'} = $_->{SHA1} foreach @{($SCM_DETAILS->{lastBuiltRevision}->{branch})};
	$api_git_url = $_ foreach @{($SCM_DETAILS->{remoteUrls})};
}

$api_artiRelativePath =  $_->{relativePath} foreach @{($JOB_CONTENT->{artifacts})};
$api_artifilename =  $_->{fileName} foreach @{($JOB_CONTENT->{artifacts})};

my $api_arti_version = `echo $api_artifilename | awk -F '-' '{print \$(NF-1)"-"\$(NF)}' | rev | cut -d. -f2- | rev`;
my $snapshot_details = $environment."::".$TENANT_NAME."::".$par_template_dir."::".$baseConfigFile."::".$API_SCM_HASH{'SHA1'}."::".$API_SCM_HASH{'branchname'}."::".$api_artifilename."::".$api_arti_version."::".$api_git_url;
#Email::notify_deployment_success($snapshot_details);

################################################
# Artifact download
my $EAR_ARTIFACT_NAME = Common::downloadJenkinsArtifact($logger,$DEPLOY_RUNTIME, $JENKINS_URL,$buildnumber,$api_artiRelativePath,$api_artifilename,
								$jenkinsUserName,$jenkinsToken,$sharedFolderPath,$masterHostname);
#my $EAR_ARTIFACT_NAME = Common::copyArtifact($logger,$DEPLOY_RUNTIME,$sharedFolderPath,$api_artifilename);

#############################
#Digi sign Package to EAR 
if ( $digiSign_status eq "true" )
{
	#############################
	# Digital Signature dependency download from NEXUS
	my $nexus_ds_filename = Nexus::downloadDSArtifact($logger,$DEPLOY_RUNTIME,$NEXUS_HOME_URL,$NEXUS_PUBLIC_REPO,
							$NEXUS_GROUP_ID,$NEXUS_ARTIFACT_ID,$NEXUS_PACKAGE_TYPE,$NEXUS_VERSION,$digiSign_status);
	
	my $tmp_status = ( !-d $DEPLOY_RUNTIME."/tmp" ) ? (make_path( $DEPLOY_RUNTIME."/tmp" , { mode => 0755}) && "Created RUNTIME temp folder") : "Already exists RUNTIME temp folder.." ;
	$logger->info($tmp_status);
	Wildfly::earPackage($logger,$DEPLOY_RUNTIME."/tmp",$EAR_ARTIFACT_NAME,$nexus_ds_filename);
}
#############################
#Deploy EAR to wildfly using management console
Wildfly::deployEar($logger,$DEPLOY_RUNTIME,$EAR_ARTIFACT_NAME,$WILDFLY_HOME,$WILDFLY_URL,$WILDFLY_MGMT_PORT,$WILDFLY_USERNAME,$WILDFLY_PASSWORD,$snapshot_details,$masterHostname,$slaveHostname,$environment,$buildnumber);

exit 0;
