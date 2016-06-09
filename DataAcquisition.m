function varargout = DataAcquisition(varargin)
% DATAACQUISITION MATLAB code for DataAcquisition.fig
%      DATAACQUISITION, by itself, creates a new DATAACQUISITION or raises the existing
%      singleton*.
%
%      H = DATAACQUISITION returns the handle to a new DATAACQUISITION or the handle to
%      the existing singleton*.
%
%      DATAACQUISITION('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in DATAACQUISITION.M with the given input arguments.
%
%      DATAACQUISITION('Property','Value',...) creates a new DATAACQUISITION or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before DataAcquisition_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to DataAcquisition_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help DataAcquisition

% Last Modified by GUIDE v2.5 09-Jun-2016 02:41:35

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @DataAcquisition_OpeningFcn, ...
                   'gui_OutputFcn',  @DataAcquisition_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before DataAcquisition is made visible.
function DataAcquisition_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to DataAcquisition (see VARARGIN)

% Choose default command line output for DataAcquisition
handles.output = hObject;

% Initiate DAQ
try
    handles.s = daq.createSession('ni');
    addAnalogInputChannel(handles.s, 'Dev1', 0:1, 'Voltage');
    handles.s.Rate = 30000;
    
    handles.ao = daq.createSession('ni');
    addAnalogOutputChannel(handles.ao, 'Dev1', 'ao0', 'Voltage');
    handles.ao.Rate = 100;
    queueOutputData(handles.ao, zeros(100,1));
    
    handles.s.IsContinuous = true;
    handles.ao.IsContinuous = true;
    display('DAQ successfully initialized.')
catch ex
    display('Problem initializing DAQ!')
    display(daq.getDevices)
end

% Initialize temporary file and file data
c = clock;
% get the folder location from the user
file.folder = [uigetdir(['C:\Data\PatchClamp\' num2str(c(1)) sprintf('%02d',c(2)) sprintf('%02d',c(3))]) '\'];
% if unable to get input from user
if isempty(file.folder)
    file.folder = ['C:\Data\PatchClamp\' num2str(c(1)) sprintf('%02d',c(2)) sprintf('%02d',c(3)) '\'];
end
file.prefix = [num2str(c(1)) '_' sprintf('%02d',c(2)) '_' sprintf('%02d',c(3))];
file.suffix = '.bin';
file.num = 0;
file.name = [file.folder file.prefix '_' sprintf('%04d',file.num) file.suffix];
file.fid = [];
handles.fileinfo = file;

% Initiate figure cache
handles.fig_cache = figure_cache(handles.axes1, 2, 5);
handles.fig_cache.clear_fig;

% Instantiate listeners
handles.listeners = [];

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes DataAcquisition wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = DataAcquisition_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on button press in x_plus.
function x_plus_Callback(hObject, eventdata, handles)
% hObject    handle to x_plus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in x_minus.
function x_minus_Callback(hObject, eventdata, handles)
% hObject    handle to x_minus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in y_plus.
function y_plus_Callback(hObject, eventdata, handles)
% hObject    handle to y_plus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in y_minus.
function y_minus_Callback(hObject, eventdata, handles)
% hObject    handle to y_minus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in play.
function play_Callback(hObject, eventdata, handles)
% hObject    handle to play (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

button_state = get(hObject,'Value');
if button_state == get(hObject,'Max')
    % Data viewing on
    try
        set(hObject,'CData',imread('Pause.png'));
        set(hObject,'String','');
        handles.fig_cache.clear_fig;
        % add listener for data
        handles.listeners.plot = addlistener(handles.s, 'DataAvailable', ...
            @(src,event) plotData(src, event, handles.fig_cache));
        guidata(hObject, handles);
        % start DAQ session
        handles.s.startBackground;
    catch ex
        set(hObject,'String','Pause');
    end
elseif button_state == get(hObject,'Min')
    % Data viewing off
    try
        handles.s.stop;
        delete(handles.listeners.plot);
        set(hObject,'CData',imread('Play.png'));
        set(hObject,'String','');
    catch ex
        set(hObject,'String','Play');
    end
end


% --- Executes on button press in record.
function record_Callback(hObject, eventdata, handles)
% hObject    handle to record (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

button_state = get(hObject,'Value');
if button_state == get(hObject,'Max')
    % Data recording on
	try
        set(hObject,'CData',imread('Recording.png'));
        set(hObject,'String','');
        handles.fig_cache.clear_fig;
        % make sure not to write over an existing file
        c = clock; % update date prefix
        prefix = [num2str(c(1)) '_' sprintf('%02d',c(2)) '_' sprintf('%02d',c(3))];
        % if there is a file with the same name in this folder
        num = handles.fileinfo.num;
        while ~isempty(ls([handles.fileinfo.folder prefix '_' sprintf('%04d',num) handles.fileinfo.suffix]))
            num = num + 1; % increment the file number for the next file
        end
        % update the handle info
        handles.fileinfo.name = [handles.fileinfo.folder prefix '_' sprintf('%04d',num) handles.fileinfo.suffix];
        handles.fileinfo.prefix = prefix;
        handles.fileinfo.num = num;
        guidata(hObject, handles);
        % get new file ready and open
        fid = fopen(handles.fileinfo.name,'w');
        % add listener for data
        handles.listeners.logAndPlot = addlistener(handles.s, 'DataAvailable', ...
            @(src,event) logDataAndPlot(src, event, fid, handles.fig_cache));
        handles.fileinfo.fid = fid;
        guidata(hObject, handles);
        display('Saving data to');
        display(handles.fileinfo.name);
        % start DAQ session
        handles.s.startBackground;
    catch ex
        set(hObject,'String','Recording!');
    end
elseif button_state == get(hObject,'Min')
    % Data recording off
	try
        fclose(handles.fileinfo.fid);
        handles.s.stop;
        delete(handles.listeners.logAndPlot);
        set(hObject,'CData',imread('Record.png'));
        set(hObject,'String','');
    catch ex
        set(hObject,'String','REC');
    end
end
