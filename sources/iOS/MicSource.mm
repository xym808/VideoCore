/*
 
 Video Core
 Copyright (C) 2014 James G. Hurley
 
 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2.1 of the License, or (at your option) any later version.
 
 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
 USA
 
 */
#include "MicSource.h"
#include <dlfcn.h>
#include <videocore/mixers/IAudioMixer.hpp>
#import <AVFoundation/AVFoundation.h>

static std::weak_ptr<videocore::iOS::MicSource> s_micSource;

static OSStatus handleInputBuffer(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    videocore::iOS::MicSource* mc =static_cast<videocore::iOS::MicSource*>(inRefCon);
    
    AudioBuffer buffer;
    buffer.mData = NULL;
    buffer.mDataByteSize = 0;
    buffer.mNumberChannels = 2;
    
    AudioBufferList buffers;
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0] = buffer;
    
    OSStatus status = AudioUnitRender(mc->audioUnit(), ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &buffers);
    
    if(!status) {
        mc->inputCallback((uint8_t*)buffers.mBuffers[0].mData, buffers.mBuffers[0].mDataByteSize);
    }
    return status;
}

namespace videocore { namespace iOS {
 
    MicSource::MicSource(std::function<void(AudioUnit&)> excludeAudioUnit) {
        
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
        [session setMode:AVAudioSessionModeVideoRecording error:nil];
        [session setActive:YES error:nil];
        
        AudioComponentDescription acd;
        acd.componentType = kAudioUnitType_Output;
        acd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
        acd.componentManufacturer = kAudioUnitManufacturer_Apple;
        acd.componentFlags = 0;
        acd.componentFlagsMask = 0;
        
        m_component = AudioComponentFindNext(NULL, &acd);
        
        AudioComponentInstanceNew(m_component, &m_audioUnit);

        if(excludeAudioUnit) {
            excludeAudioUnit(m_audioUnit);
        }
        UInt32 flagOne = 1;
        
        AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flagOne, sizeof(flagOne));
        
        AudioStreamBasicDescription desc = {0};
        desc.mSampleRate = 44100.;
        desc.mFormatID = kAudioFormatLinearPCM;
        desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        desc.mChannelsPerFrame = 2;
        desc.mFramesPerPacket = 1;
        desc.mBitsPerChannel = 16;
        desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
        desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
        
        AURenderCallbackStruct cb;
        cb.inputProcRefCon = this;
        cb.inputProc = handleInputBuffer;
        AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desc, sizeof(desc));
        AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));
        
        AudioUnitInitialize(m_audioUnit);
        AudioOutputUnitStart(m_audioUnit);
    }
    MicSource::~MicSource() {
        auto output = m_output.lock();
        if(output) {
            auto mixer = std::dynamic_pointer_cast<IAudioMixer>(output);
            mixer->unregisterSource(shared_from_this());
        }
        AudioOutputUnitStop(m_audioUnit);
        AudioComponentInstanceDispose(m_audioUnit);
    }
    void
    MicSource::inputCallback(uint8_t *data, size_t data_size)
    {
        auto output = m_output.lock();
        if(output) {
            videocore::AudioBufferMetadata md (0.);
            md.setData(44100, 16, 2, false, shared_from_this());
            output->pushBuffer(data, data_size, md);
        }
    }
    void
    MicSource::setOutput(std::shared_ptr<IOutput> output) {
        m_output = output;
        auto mixer = std::dynamic_pointer_cast<IAudioMixer>(output);
        mixer->registerSource(shared_from_this());
    }
}
}
