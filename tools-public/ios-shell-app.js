// Copyright 2015-present 650 Industries. All rights reserved.

'use strict';

import 'instapromise';

import crayon from '@ccheever/crayon';
import fs from 'fs';
import shell from 'shelljs';
import path from 'path';
import { getManifestAsync, saveUrlToPathAsync } from './shell-app-utils';
import {
  modifyIOSPropertyListAsync,
  cleanIOSPropertyListBackupAsync,
} from './ios-utils';

function validateConfigArguments(manifest, cmdArgs, configFilePath) {
  if (!configFilePath) {
    throw new Error('No path to config files provided');
  }
  if ((!manifest.ios && !cmdArgs.bundleIdentifier) ||
      (!manifest.ios.bundleIdentifier && !cmdArgs.bundleIdentifier)) {
    throw new Error('No bundle identifier found in either the manifest or argv');
  }
  if (!manifest.name) {
    throw new Error('Manifest does not have a name');
  }

  if (!cmdArgs.privateConfigFile) {
    crayon.yellow.warn('Warning: No config file specified.');
  }
  return true;
}

/**
 * Writes Fabric config to private-shell-app-config.json if necessary. Used by
 * generate-dynamic-macros when building.
 */
async function configureShellAppSecretsAsync(args, iosDir) {
  if (!args.privateConfigFile) {
    return;
  }

  shell.exec(`cp ${args.privateConfigFile} ${path.join(iosDir, 'private-shell-app-config.json')}`);
}

async function configurePropertyListsAsync(manifest, args, configFilePath) {
  // make sure we have all the required info
  validateConfigArguments(manifest, args, configFilePath);
  console.log(`Modifying config files under ${configFilePath}...`);

  let {
    url,
    bundleIdentifier,
    privateConfigFile,
  } = args;

  let privateConfig;
  if (privateConfigFile) {
    let privateConfigContents = await fs.promise.readFile(privateConfigFile, 'utf8');
    privateConfig = JSON.parse(privateConfigContents);
  }

  // generate new shell config
  await modifyIOSPropertyListAsync(configFilePath, 'EXShell', (shellConfig) => {
    shellConfig.isShell = true;
    shellConfig.manifestUrl = shellConfig.manifestUrl || url;
    if (manifest.ios && manifest.ios.permissions) {
      shellConfig.permissions = manifest.ios.permissions;
    }

    console.log('Using shell config:', shellConfig);
    return shellConfig;
  });

  // modify Info.plist based on manifest
  await modifyIOSPropertyListAsync(configFilePath, 'Info', (config) => {
    // bundle id
    config.CFBundleIdentifier = manifest.ios.bundleIdentifier || bundleIdentifier;

    // app name
    config.CFBundleName = manifest.name;

    // determine app linking schemes
    let linkingSchemes = (manifest.scheme) ? [manifest.scheme] : [];
    if (manifest.facebookScheme && manifest.facebookScheme.startsWith('fb')) {
      linkingSchemes.push(manifest.facebookScheme);
    }

    // remove exp scheme, add app scheme(s)
    config.CFBundleURLTypes = [{
      CFBundleURLSchemes: linkingSchemes,
    }];

    // use shell-specific launch screen
    config.UILaunchStoryboardName = 'LaunchScreenShell';

    // permanently save the exponent client version at time of configuration
    config.EXClientVersion = config.CFBundleVersion;

    // use version from manifest
    let version = (manifest.version) ? manifest.version : '0.0.0';
    config.CFBundleShortVersionString = version;
    config.CFBundleVersion = version;

    let internalKeys;
    try {
      internalKeys = require('../__internal__/keys.json');
    } catch (e) {
      internalKeys = require('../template-files/keys.json');
    }
    const defaultFabricKey = internalKeys.FABRIC_API_KEY;

    config.Fabric = {
      APIKey: (privateConfig && privateConfig.fabric && privateConfig.fabric.apiKey) || defaultFabricKey,
      Kits: [{
        KitInfo: {},
        KitName: 'Crashlytics',
      }],
    };

    return config;
  });
}

/**
 * Ensure that the proper icon images exist -- Info.plist already points at them
 * under CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles
 */
async function configureIconsAsync(manifest, args, configFilePath) {
  let defaultIconFilename;
  if (manifest.iconUrl) {
     defaultIconFilename = 'exp-icon.png';
     await saveUrlToPathAsync(manifest.iconUrl, `${configFilePath}/${defaultIconFilename}`);
   }

  let iconSizes = [29, 40, 60];
  let iconResolutions = [2, 3];
  iconSizes.forEach(iconSize => {
    iconResolutions.forEach(async (iconResolution) => {
      let iconQualifier = `${iconSize}x${iconSize}@${iconResolution}x`;
      let iconKey = `iconUrl${iconQualifier}`;
      let rawIconFilename;
      let usesDefault = false;
      if (manifest.ios && manifest.ios.hasOwnProperty(iconKey)) {
        // manifest specifies an image just for this size/resolution, use that
        rawIconFilename = `exp-icon${iconQualifier}.png`;
        await saveUrlToPathAsync(manifest.ios[iconKey], `${configFilePath}/${rawIconFilename}`);
      } else {
        // use default manifest.iconUrl
        usesDefault = true;
        if (defaultIconFilename) {
          rawIconFilename = defaultIconFilename;
        } else {
          console.warn(`Manifest does not specify ios.${iconKey} nor a default iconUrl. Bundle will use the Exponent logo.`);
          return;
        }
      }
      let iconFilename = `AppIcon${iconQualifier}.png`;
      let iconSizePx = iconSize * iconResolution;
      let iconCommands = [
        `pushd ${configFilePath}`,
        `cp ${rawIconFilename} ${iconFilename}`,
        `sips -Z ${iconSizePx} ${iconFilename}`,
      ];
      if (!usesDefault) {
        // non-default icon used, clean up the downloaded version
        iconCommands = iconCommands.concat([`rm ${rawIconFilename}`]);
      }
      shell.exec(iconCommands.join(' && '));
    });
  });

  // clean up default icon
  if (defaultIconFilename) {
    shell.exec(`rm ${configFilePath}/${defaultIconFilename}`);
  }
  return;
}

/**
 * Write the manifest and JS bundle to the iOS NSBundle.
 */
async function preloadManifestAndBundleAsync(manifest, args, configFilePath) {
  let bundleUrl = manifest.bundleUrl;
  await fs.promise.writeFile(`${configFilePath}/shell-app-manifest.json`, JSON.stringify(manifest));
  await saveUrlToPathAsync(bundleUrl, `${configFilePath}/shell-app.bundle`);
  return;
}

async function cleanPropertyListBackupsAsync(configFilePath, restoreOriginals) {
  console.log('Cleaning up...');
  await cleanIOSPropertyListBackupAsync(configFilePath, 'EXShell', restoreOriginals);
  await cleanIOSPropertyListBackupAsync(configFilePath, 'Info', restoreOriginals);
}

/**
 *  Build the iOS binary from source.
 *  @return the path to the resulting .app
 */
async function buildAsync(args, iOSRootPath, relativeBuildDestination) {
  let { action, configuration, verbose, type } = args;

  let buildCmd, buildDest, pathToApp;
  if (type === 'simulator') {
    buildDest = `${iOSRootPath}/${relativeBuildDestination}-simulator`;
    buildCmd = `xcodebuild -workspace Exponent.xcworkspace -scheme Exponent -sdk iphonesimulator -configuration ${configuration} -arch i386 -derivedDataPath ${buildDest} CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO SKIP_INSTALL=NO | xcpretty`;
    pathToApp = `${buildDest}/Build/Products/${configuration}-iphonesimulator/Exponent.app`;
  } else if (type === 'archive') {
    buildDest = `${iOSRootPath}/${relativeBuildDestination}-archive`;
    buildCmd = `xcodebuild -workspace Exponent.xcworkspace -scheme Exponent archive -configuration ${configuration} -derivedDataPath ${buildDest} -archivePath ${buildDest}/Exponent.xcarchive CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO SKIP_INSTALL=NO | xcpretty`;
    pathToApp = `${buildDest}/Exponent.xcarchive/Products/Applications/Exponent.app`;
  }

  if (buildCmd) {
    if (!verbose) {
      buildCmd = `${buildCmd} > /dev/null`;
    }

    console.log(`Building shell app under ${iOSRootPath}/${relativeBuildDestination}`);
    console.log(`  (action: ${action}, configuration: ${configuration})...`);
    console.log(buildCmd);
    shell.exec(`pushd ${iOSRootPath} && ${buildCmd}`);

    let artifactLocation = `${iOSRootPath}/../shellAppBase-builds/${type}/${configuration}/`;
    shell.rm('-rf', artifactLocation);
    shell.mkdir('-p', artifactLocation);

    if (type === 'archive') {
      shell.cp('-R', `${buildDest}/Exponent.xcarchive`, artifactLocation);
    } else if (type === 'simulator') {
      shell.cp('-R', pathToApp, artifactLocation);
    }

  }
  return pathToApp;
}

function validateArgs(args) {
  args.type = args.type || 'archive';
  args.configuration = args.configuration || 'Release';
  args.verbose = args.verbose || false;

  switch (args.type) {
    case 'simulator': {
      if (args.configuration !== 'Debug' && args.configuration !== 'Release') {
        throw new Error(`Unsupported build configuration ${args.configuration}`);
      }
      break;
    }
    case 'archive': {
      if (args.configuration !== 'Release') {
        throw new Error('Release is the only supported configuration when archiving');
      }
      break;
    }
    default: {
      throw new Error(`Unsupported build type ${args.type}`);
    }
  }

  switch (args.action) {
    case 'configure': {
      if (!args.url) {
        throw new Error('Must run with `--url MANIFEST_URL`');
      }
      if (!args.sdkVersion) {
        throw new Error('Must run with `--sdkVersion SDK_VERSION`');
      }
      if (!args.archivePath) {
        throw new Error('Need to provide --archivePath <path to existing archive for configuration>');
      }
      break;
    }
    case 'build': {
      break;
    }
    default: {
      throw new Error(`Unsupported build action ${args.action}`);
    }
  }

  return args;
}

/**
*  @param url manifest url for shell experience
*  @param sdkVersion sdk to use when requesting the manifest
*  @param action
*    build - build a binary
*    configure - don't build anything, just configure the files in an existing .app bundle
*  @param type simulator or archive, for action == build
*  @param configuration Debug or Release, for type == simulator (default Release)
*  @param archivePath path to existing bundle, for action == configure
*  @param privateConfigFile path to a private config file containing, e.g., private api keys
*  @param bundleIdentifier iOS CFBundleIdentifier to use in the bundle config
*  @param verbose show all xcodebuild output (default false)
*/
export async function createIOSShellAppAsync(args) {
  let configFilePath;
  args = validateArgs(args);

  if (args.action !== 'configure') {
    // build the app before configuring
    await configureShellAppSecretsAsync(args, '../ios');
    configFilePath = await buildAsync(args, '../ios', '../shellAppBase');
  } else {
    let {
      url,
      sdkVersion,
      output,
      type,
    } = args;

    // fetch manifest
    let manifest = await getManifestAsync(url, {
      'Exponent-SDK-Version': sdkVersion,
      'Exponent-Platform': 'ios',
    });

    // action === 'configure'
    configFilePath = args.archivePath;
    // just configure, don't build anything
    await configurePropertyListsAsync(manifest, args, configFilePath);
    await configureIconsAsync(manifest, args, configFilePath);
    await preloadManifestAndBundleAsync(manifest, args, configFilePath);
    await cleanPropertyListBackupsAsync(configFilePath, false);

    let archiveName = manifest.name.replace(/\s+/g, '');
    if (type === 'simulator') {
      shell.exec(`cd ${configFilePath}/.. && mv Exponent.app ${archiveName}.app && tar cvf ${output} ${archiveName}.app`);
    } else if (type === 'archive') {
      shell.exec(`cd ${configFilePath}/../../../.. && mv Exponent.xcarchive ${output}`);
    }
  }

  return;
}
