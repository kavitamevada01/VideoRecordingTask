/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 * @flow
 */

import React, { Component } from 'react';
import {
   NativeModules,
  AppRegistry,
  StyleSheet,
  Text,
  View,
   TextInput,
  DeviceEventEmitter,
  TouchableHighlight,
  TouchableOpacity
} from 'react-native';

var ScreenRecordingRCTModule = NativeModules.ScreenRecordingRCTModule;

class VideoRecordingTask extends Component {
	
	constructor(props) { 
		super(props);
		var CompleVideoRecordingListner = DeviceEventEmitter.addListener(
 						   'VideoRecordingCompleteListner',
   						 	(response) => {
								
								if(response.status=="1") //Recording Comple
								{
									console.log(response.VideoFile);
									console.log(response.Message);
								}
								else //Recording Error
								{
									console.log(response.Message);
								}
								
							}
						); 
	}
  render() {
    return (
      <View style={styles.container}>
        <Text style={styles.welcome}>
          Welcome to React Native!
        </Text>
         <View style={styles.RowContainer}>
				 <TouchableOpacity onPress={this._StartVideoRecording}>
			 		 <View style={styles.container}>
        				<View style={styles.button}> 
          			 		<Text style={styles.buttonText}>Start video</Text>
         	  		 	</View>
      		  		 </View>
			 	</TouchableOpacity>
				<TouchableOpacity onPress={this._StopVideoRecording}>
			 		 <View style={styles.container}>
        				<View style={styles.button}> 
          			 		<Text style={styles.buttonText}>Stop Video</Text>
         	  		 	</View>
      		  		 </View>
			 	</TouchableOpacity>
		 </View>
      </View>
    );
  }
  
    _StartVideoRecording(event) {
	   var milliseconds = new Date().getTime();
	   var FileName= milliseconds+"Video";
	   var VideoSettings = {VideoFileName: FileName,VideoWidth:800,VideoHeight:800,VideoX:300,VideoY:500,isRecordSound:0,isRecordGifFormat:0};
	   
	   ScreenRecordingRCTModule.StartScreenRecordingInVideoFormat(VideoSettings, (error, responseData) =>       { 
	  		console.log(error);
			console.log(responseData);
	   });
   }
   _StopVideoRecording(event) {
	   
	   ScreenRecordingRCTModule.StopScreenRecordingInVideoFormat((error, responseData) =>       { 
	  		console.log(error);
			console.log(responseData);
	   });
   }
}

const styles = StyleSheet.create({
  container: {
     paddingTop:1,
	 marginTop:0.1
  },
  welcome: {
    fontSize: 20,
    textAlign: 'center',
    margin: 10,
  },
  instructions: {
    textAlign: 'center',
    color: '#333333',
    marginBottom: 5,
  },
   RowContainer: {
    paddingTop:1,
	flexDirection:'row',
	flexWrap:'wrap',
	marginTop:0,
  },
  labelTitle: {
    fontSize: 14,
    textAlign: 'left',
    margin: 10,
    color: '#3667AF',
    alignSelf: 'auto',
  },
  button: {
    margin: 10,
    width: 100,
	height: 20,
    backgroundColor: '#4479BA',
    alignSelf: 'flex-start',
  },
   buttonText: {
  	fontSize: 12,
    padding:4,
    textAlign: 'center',
    color: '#FFF',
    alignSelf: 'auto',
  },
});

AppRegistry.registerComponent('VideoRecordingTask', () => VideoRecordingTask);
