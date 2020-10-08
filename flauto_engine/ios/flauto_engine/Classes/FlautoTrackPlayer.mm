/*
 * Copyright 2018, 2019, 2020 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License version 3 (LGPL-V3), as published by
 * the Free Software Foundation.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with Flutter-Sound.  If not, see <https://www.gnu.org/licenses/>.
 */




#import "FlautoTrackPlayer.h"
#import "FlautoTrack.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>




//---------------------------------------------------------------------------------------------

@implementation FlautoTrackPlayer
{
       NSURL *audioFileURL;
       Track *track;
       id forwardTarget;
       id backwardTarget;
       id pauseTarget;
       id togglePlayPauseTarget;
       id stopTarget;
       id playTarget;
       MPMediaItemArtwork* albumArt ;
       BOOL defaultPauseResume;
       BOOL removeUIWhenStopped;
}
- (FlautoTrackPlayer*)init: (NSObject<FlautoPlayerCallback>*) callback;
{
        return [super init: callback];
}


- (void)releaseFlautoPlayer;
{
        NSLog(@"IOS:--> releaseFlautoPlayer");
        [self stopPlayer];
        [self cleanNowPlaying];
        removeUIWhenStopped = true;
        [self cleanTarget];
        [super releaseFlautoPlayer];
        NSLog(@"IOS:<-- releaseFlautoPlayer");
}

- (AVAudioPlayer*)getPlayer
{
        return [(AudioPlayer*)m_playerEngine  getAudioPlayer];
        
}

- (void)setPlayer:(AVAudioPlayer*) theAudioPlayer
{
        [(AudioPlayer*)m_playerEngine  setAudioPlayer: theAudioPlayer];
}

- (bool)startPlayerFromTrack: (Track*)track canPause: (bool)canPause canSkipForward: (bool)canSkipForward canSkipBackward: (bool)canSkipBackward
        progress: (NSNumber*)progress duration: (NSNumber*)duration removeUIWhenStopped: (bool)removeUIWhenStopped defaultPauseResume: (bool)defaultPauseResume;
{
         NSLog(@"IOS:--> startPlayerFromTrack");
         bool r = FALSE;

        if(!track)
        {
                return false;
        }
        [self stopPlayer]; // to start a fresh new playback

        m_playerEngine = [[AudioPlayer alloc]init: self];

        // Check whether the audio file is stored as a path to a file or a buffer
        if([track isUsingPath])
        {
                // The audio file is stored as a path to a file

                NSString *path = track.path;

                bool isRemote = false;

                // A path was given, then create a NSURL with it
                NSURL *remoteUrl = [NSURL URLWithString:path];

                // Check whether the URL points to a local or remote file
                if(remoteUrl && remoteUrl.scheme && remoteUrl.host)
                {
                        audioFileURL = remoteUrl;
                        isRemote = true;
                } else
                {
                        audioFileURL = [NSURL URLWithString:path];
                }

                if (!hasFocus) // We always acquire the Audio Focus (It could have been released by another session)
                {
                        hasFocus = TRUE;
                        r = [[AVAudioSession sharedInstance]  setActive: hasFocus error:nil] ;
                }



                // Check whether the file path points to a remote or local file
                if (isRemote)
                {
                        NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
                                                  dataTaskWithURL:audioFileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                      // The file to play has been downloaded, then initialize the audio player
                                                      // and start playing.

                                                      // We must create a new Audio Player instance to be able to play a different Url
                                                      [self setPlayer: [[AVAudioPlayer alloc] initWithData:data error:nil] ];
                                                      [self getPlayer].delegate = self;

                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          NSLog(@"IOS: ^beginReceivingRemoteControlEvents");
                                                          [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
                                                      });

                                                      [[self getPlayer] play];
                                                   }];
                        r = true; // ??? not sure
                        [downloadTask resume];
                        //[self startTimer];
                } else
                {
                        // Initialize the audio player with the file that the given path points to,
                        // and start playing.
                        [self setPlayer: [[AVAudioPlayer alloc] initWithContentsOfURL: audioFileURL error:nil] ];
                        [self getPlayer].delegate = self;
                        // }

                        // Able to play in silent mode
                        dispatch_async(dispatch_get_main_queue(),
                        ^{
                                NSLog(@"^beginReceivingRemoteControlEvents");
                                [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
                        });

                        r = [[self getPlayer] play];
                        if (![[self getPlayer] isPlaying])
                                NSLog(@"IOS: AudioPlayer failed to play");
                        else
                                NSLog(@"IOS: !Play");
                        //[self startTimer];
                }
        } else
        {
        // The audio file is stored as a buffer
                NSData* bufferData = track.dataBuffer;
                [self setPlayer: ([[AVAudioPlayer alloc] initWithData: bufferData error: nil]) ];
                [self getPlayer].delegate = self;
                dispatch_async(dispatch_get_main_queue(),
                ^{
                        NSLog(@"^beginReceivingRemoteControlEvents");
                        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
                });
                r = [[self getPlayer] play];
                if (![[self getPlayer] isPlaying])
                        NSLog(@"IOS: AudioPlayer failed to play");
                else
                        NSLog(@"IOS: !Play");
        }
        if (r)
        {
                [self startTimer];
                // Display the notification with the media controls
                [self setupRemoteCommandCenter:canPause canSkipForward:canSkipForward   canSkipBackward:canSkipBackward ];
                
                if ( (progress == nil) || (progress.class == NSNull.class) )
                        progress = [NSNumber numberWithDouble: [self getPlayer].currentTime];
                else
                        progress = [NSNumber numberWithDouble: [progress doubleValue] / 1000.0];
                if ( (duration == nil) || (duration.class == NSNull.class) )
                        duration = [NSNumber numberWithDouble: [self getDuration] / 1000.0];
                else
                        duration = [NSNumber numberWithDouble: [duration doubleValue] / 1000.0];
                [self setupNowPlaying: progress duration: duration];
                

                long duration = [self getDuration];
                [ m_callBack startPlayerCompleted: duration];
        }
        return r;
}



// Give the system information about what the audio player
// is currently playing. Takes in the image to display in the
// notification to control the media playback.
- (void)setupNowPlaying: (NSNumber*) progress duration: (NSNumber*)duration
{
        NSLog(@"IOS:--> setupNowPlaying");

        // Initialize the MPNowPlayingInfoCenter

         albumArt = nil;
        // The caller specify an asset to be used.
        // Probably good in the future to allow the caller to specify the image itself, and not a resource.
        if ((track.albumArtUrl != nil) && ([track.albumArtUrl class] != [NSNull class])   )         // The albumArt is accessed in a URL
        {
                // Retrieve the album art for the
                // current track .
                NSURL* url = [NSURL URLWithString:self->track.albumArtUrl];
                UIImage* artworkImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
                if(artworkImage)
                {
                        albumArt = [[MPMediaItemArtwork alloc] initWithImage: artworkImage];
                }
        } else
        if ((track.albumArtAsset) && ([track.albumArtAsset class] != [NSNull class])   )        // The albumArt is an Asset
        {
                UIImage* artworkImage = [UIImage imageNamed: track.albumArtAsset];
                if (artworkImage != nil)
                {
                        albumArt = [ [MPMediaItemArtwork alloc] initWithImage: artworkImage ];

                }
        } else
        if ((track.albumArtFile) && ([track.albumArtFile class] != [NSNull class])   )          //  The AlbumArt is a File
        {
                UIImage* artworkImage = [UIImage imageWithContentsOfFile: track.albumArtFile];
                if (artworkImage != nil)
                {
                        albumArt = [[MPMediaItemArtwork alloc] initWithImage: artworkImage];
                }
        } else // Nothing specified. We try to use the App Icon
        {
                UIImage* artworkImage = [UIImage imageNamed: @"AppIcon"];
                if (artworkImage != nil)
                {
                        albumArt = [[MPMediaItemArtwork alloc] initWithImage: artworkImage];
                }
        }
        [ self setUIProgressBar: progress duration: duration ];
        NSLog(@"IOS:<-- setupNowPlaying");

}


- (void)cleanTarget
{
          NSLog(@"IOS:--> cleanTarget");
          MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

          if (togglePlayPauseTarget != nil)
          {
                [commandCenter.togglePlayPauseCommand removeTarget: togglePlayPauseTarget action: nil];
                togglePlayPauseTarget = nil;
          }

          if (pauseTarget != nil)
          {
                [commandCenter.pauseCommand removeTarget: pauseTarget action: nil];
                pauseTarget = nil;
          }

          if (playTarget != nil)
          {
                [commandCenter.playCommand removeTarget: playTarget action: nil];
                playTarget = nil;
          }

          if (stopTarget != nil)
          {
                [commandCenter.stopCommand removeTarget: stopTarget action: nil];
                stopTarget = nil;
          }

          if (forwardTarget != nil)
          {
                [commandCenter.nextTrackCommand removeTarget: forwardTarget action: nil];
                forwardTarget = nil;
          }

          if (backwardTarget != nil)
          {
                [commandCenter.previousTrackCommand removeTarget: backwardTarget action: nil];
                backwardTarget = nil;
          }
          
      
          //albumArt = nil;
          NSLog(@"IOS:<-- cleanTarget");
 }

- (void)stopPlayer
{

          NSLog(@"IOS:--> stopPlayer");
          [self stopTimer];
          if ([self getPlayer] != nil)
          {
                NSLog(@"IOS: !stopPlayer");
                [[self getPlayer] stop];
                [self setPlayer: nil];
          }
          if (removeUIWhenStopped)
          {
                [self cleanTarget];
                MPNowPlayingInfoCenter* playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
                [playingInfoCenter setNowPlayingInfo: nil];
                playingInfoCenter.nowPlayingInfo = nil;
          }
          NSLog(@"IOS:<-- stopPlayer");
}



// Give the system information about what to do when the notification
// control buttons are pressed.
- (void)setupRemoteCommandCenter:(BOOL)canPause canSkipForward:(BOOL)canSkipForward canSkipBackward:(BOOL)canSkipBackward
{
        NSLog(@"IOS:--> setupRemoteCommandCenter");
        [self cleanTarget];
        MPRemoteCommandCenter* commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
        if (canPause)
        {

                togglePlayPauseTarget = [commandCenter.togglePlayPauseCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        NSLog(@"IOS: toggleTarget\n");
                        dispatch_async(dispatch_get_main_queue(), ^{
 
 
                                bool b = [[self getPlayer] isPlaying];
                                // If the caller wants to control the pause button, just call him
                                if (b)
                                {
                                        if (self ->defaultPauseResume)
                                                [self pausePlayer];
                                        [self ->m_callBack pause];
                                } else
                                {
                                        if ( self ->defaultPauseResume)
                                                [self resumePlayer];
                                        [self ->m_callBack resume];
                                }
                        });
                        return MPRemoteCommandHandlerStatusSuccess;
                }];

                pauseTarget = [commandCenter.pauseCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        NSLog(@"IOS: pauseTarget\n");
                        dispatch_async(dispatch_get_main_queue(), ^{
                                bool b = [[self getPlayer] isPlaying];
                                // If the caller wants to control the pause button, just call him
                                if (b)
                                {
                                        if (self ->defaultPauseResume)
                                                [self pausePlayer];
                                        [self ->m_callBack pause];                                }
                        });
                        return MPRemoteCommandHandlerStatusSuccess;
                 }];

                stopTarget = [commandCenter.stopCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        NSLog(@"IOS: stopTarget\n");
                        return MPRemoteCommandHandlerStatusSuccess;
                }];


                playTarget = [commandCenter.playCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        NSLog(@"IOS: playTarget\n");
                        dispatch_async(dispatch_get_main_queue(), ^{
                                bool b = [[self getPlayer] isPlaying];
                                // If the caller wants to control the pause button, just call him
                                if (!b)
                                {
                                        if (self ->defaultPauseResume)
                                                [self resumePlayer];
                                       [self ->m_callBack resume];
                                }
                        });
                                
                        return MPRemoteCommandHandlerStatusSuccess;
                }];
        }

        commandCenter.togglePlayPauseCommand.enabled = canPause;
        commandCenter.playCommand.enabled = canPause;
        commandCenter.stopCommand.enabled = canPause;
        commandCenter.pauseCommand.enabled = canPause;

        [commandCenter.togglePlayPauseCommand setEnabled: canPause]; // If the caller does not want to control pause button, we will use our default action
        [commandCenter.playCommand setEnabled: canPause]; // If the caller does not want to control pause button, we will use our default action
        [commandCenter.stopCommand setEnabled: canPause]; // If the caller does not want to control pause button, we will use our default action
        [commandCenter.pauseCommand setEnabled: canPause]; // If the caller does not want to control pause button, we will use our default action

        [commandCenter.nextTrackCommand setEnabled:canSkipForward];
        [commandCenter.previousTrackCommand setEnabled:canSkipBackward];


        if (canSkipForward)
        {
                forwardTarget = [commandCenter.nextTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        [self ->m_callBack skipForward];
                        return MPRemoteCommandHandlerStatusSuccess;
                }];
        }

        if (canSkipBackward)
        {
                backwardTarget = [commandCenter.previousTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event)
                {
                        [self ->m_callBack skipBackward];
                        return MPRemoteCommandHandlerStatusSuccess;
                }];
        }
       NSLog(@"IOS:<-- setupRemoteCommandCenter");
 }

- (void)setUIProgressBar: (NSNumber*)progress duration: (NSNumber*)duration
{
        NSLog(@"IOS:--> setUIProgressBar");
        NSMutableDictionary* songInfo = [[NSMutableDictionary alloc] init];

        if ( (progress != nil) && ([progress class] != [NSNull class]) && (duration != nil) && ([duration class] != [NSNull class]))
        {
                NSLog(@"IOS: setUIProgressBar Progress: %@ s.", progress);
                NSLog(@"IOS: setUIProgressBar Duration: %@ s.", duration);
                [songInfo setObject: progress forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime];
                [songInfo setObject: duration forKey: MPMediaItemPropertyPlaybackDuration];
        }

        if (albumArt != nil)
        {
                       [songInfo setObject:albumArt forKey: MPMediaItemPropertyArtwork];
        }

        if (track != nil)
        {
                [songInfo setObject: track.title forKey: MPMediaItemPropertyTitle];
                [songInfo setObject: track.author forKey: MPMediaItemPropertyArtist];
        }
        bool b = [[self getPlayer] isPlaying];
        [songInfo setObject:[NSNumber numberWithDouble:(b ? 1.0f : 0.0f)] forKey:MPNowPlayingInfoPropertyPlaybackRate];
        

        MPNowPlayingInfoCenter* playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
        [playingInfoCenter setNowPlayingInfo: songInfo];
        NSLog(@"IOS:<-- setUIProgressBar");

}

- (void)updateLockScreenProgression
{
        NSLog(@"IOS:--> updateLockScreenProgression");
        NSNumber* progress = [NSNumber numberWithDouble: [self getPosition]] ;
        NSNumber* duration = [NSNumber numberWithDouble: [self getDuration]];
        [self setUIProgressBar: progress duration: duration];
        NSLog(@"IOS:<-- updateLockScreenProgression");
}



- (void)cleanNowPlaying
{
                MPNowPlayingInfoCenter* playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
                [playingInfoCenter setNowPlayingInfo: nil];
                playingInfoCenter.nowPlayingInfo = nil;

}


- (void)nowPlaying: (Track*)track canPause: (bool)canPause canSkipForward: (bool)canSkipForward canSkipBackward: (bool)canSkipBackward
                defaultPauseResume: (bool)defaultPauseResume progress: (NSNumber*)progress duration: (NSNumber*)duration
{
         NSLog(@"IOS:--> nowPlaying");
         track = nil;
  
   
        [self setupRemoteCommandCenter:canPause canSkipForward:canSkipForward   canSkipBackward:canSkipBackward ];
        if ( !track  )
        {
                [self cleanNowPlaying];
                return;
        }

        if ( (progress != nil) && ([progress class] != [NSNull class]))
        {
                double x = [ progress doubleValue];
                progress = [NSNumber numberWithFloat: x/1000.0];
        }
        if ( (duration != nil) && ([duration class] != [NSNull class]))
        {
                double y = [ duration doubleValue];
                duration = [NSNumber numberWithFloat: y/1000.0];
        }


        [self setupNowPlaying: progress duration: duration];
        NSLog(@"IOS:<-- nowPlaying");

}



- (void)seekToPlayer: (long)time;
{

        NSLog(@"IOS:--> seekToPlayer");
        [super seekToPlayer: time];
        [self updateLockScreenProgression];
        NSLog(@"IOS:<-- seekToPlayer");
  }
  
  
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
        NSLog(@"IOS:--> audioPlayerDidFinishPlaying");
        if (removeUIWhenStopped)
        {
                [self cleanTarget];
                MPNowPlayingInfoCenter* playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
                [playingInfoCenter setNowPlayingInfo: nil];
                playingInfoCenter.nowPlayingInfo = nil;
        }

        [super audioPlayerDidFinishPlaying: player successfully: flag];
        NSLog(@"IOS:<-- audioPlayerDidFinishPlaying");
}

@end
