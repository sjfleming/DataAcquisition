DataAcquisition
=======

## What

DataAcquisition is an open-source graphical user interface for viewing and recording data from a National Instruments DAQ in real time.  Specifically developed for patch-clamp electrophysiology recordings, DataAcquisition together with the NI DAQ USB-6003 provide an alternative to [Axon's pCLAMP software](https://www.moleculardevices.com/systems/axon-conventional-patch-clamp/pclamp-11-software-suite) together with the [DigiData](https://www.moleculardevices.com/systems/conventional-patch-clamp/digidata-1550-digitizer) analog-to-digital converter.

![](http://s7d5.scene7.com/is/image/ni/04231404?$ni-card-md$)


## Usage

```matlab
d = DataAcquisition();
```

Optionally, you can input Channels, Alphas, OutputAlpha, and SampleFrequency:

```Channels``` is a vector (maximum of four elements) containing the integers 0 through 3 that specifies which channels are inputs. 
	e.g. [0, 1]
	Note: specify the scalings for all inputs and outputs if you specify any.

```Alphas``` is a vector of scale factors to apply to analog inputs (to convert measured values to either pA or mV).
	Note: you must specify the scale factors for all inputs if you specify any.
  
```OutputAlpha``` is a numeric scale factor to be applied to the analog output (to convert values in mV to voltage output in the range [-10,10] Volts).

```SampleFrequency``` is a numeric value that specifies the frequency at which data are sampled.  Default is 25kHz.
  Note: due to hardware limitations, the upper limit is 100kHz divided by the number of input channels.


## Example Usage

... screenshots forthcoming.  It's a GUI.

## Who

Stephen Fleming, PhD candidate at the Golovchenko Lab in the physics department at Harvard University.
