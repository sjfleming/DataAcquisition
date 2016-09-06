classdef DataAcquisition < handle
% DATAACQUISITION is a Matlab program for electronic signal acquistion from
% a National Instruments DAQ USB-6003.

% This software was written with Patch Clamp and electrophysiological
% measurements in mind, although it could also be used as a simple
% oscilloscope and data recording tool.
%
% DataAcquisition has the following modes of operation:
% "Normal Acquisition":
%   An oscilloscope mode, enabling live data viewing as well as "gap-free" 
%   recording.
% "Noise Plot":
%   A live noise plot is displayed on the screen and is periodically
%   refreshed, allowing the user to identify noise sources, make changes in
%   an experiment, and see their effects in real time.
% "IV Acquisition":
%   Programmable, periodic voltage stimulation allows the user to make a
%   recording of current versus voltage.  This feature displays the results
%   on screen in a second panel.
% "Seal Test":
%   A mode used for examining capacitance.  Reapeatedly
%   applies a voltage step function and displays the resulting current
%   response.  This mode is useful in patch clamp experiments, where the
%   user can adjust capacitance compensation to offset the current spikes
%   which accompany the voltage steps.
%
% Use of the functionality specific to electrophysiology measurements (IV
% curve and membrane seal test) require the analog output terminal ao0 to
% be connected to an external command input on the current amplifier.
%
% Data is saved in a .dbf file format in the folder specified by the user.
% The .dbf file format, for "Dataacquisition Binary Format," is a binary
% file which contains a header followed by the signal data, and can be
% opened using Tamas Szalay's PoreView software, with the appropriate
% additions for .dbf handling.

% Stephen Fleming 2016.08.13

    properties
        fig         % Handle for the entire DataAcquisition figure
        DAQ         % Matlab DAQ object handle
        file        % Information about the next data file to be saved
        mode        % Which program is running: normal, noise, iv, sealtest
        alpha       % Conversion factors from input to real signal
        outputAlpha % Conversion factor for output
        channels    % Channels for data acquisition
        sampling    % Sampling frequency for input channels
    end 
    
    properties (Hidden=true)
        panel       % Handle for main display panel
        axes        % Handle for the main axes
        fig_cache   % Handle for cache object that handles live data
        DEFS        % UI definitions (widths etc.)
        tabs        % Main window tabs handle struct
        hcmenu      % Handle to context menu
        tbuts       % Handles for the main control buttons
        ybuts       % Handles for the y axis buttons
        xbuts       % Handles for the x axis buttons
        outputFreq  % Frequency of analog output signal
        audio       % Matlab audio player object
        data_compression_scaling    % compression to int16
    end

    methods (Hidden=true)
        
        function obj = DataAcquisition(varargin)
            % Constructor
            
            % Handle inputs
            inputs = obj.parseInputs(varargin);
            obj.channels = inputs.Channels;
            obj.alpha = inputs.Alphas;
            obj.sampling = inputs.SampleFrequency;
            obj.outputAlpha = inputs.OutputAlpha;
            
            % Figure out scale factor for data compression
            obj.data_compression_scaling = (2^15-1)./obj.alpha/10; % range of 10V
            
            % Set constants
            obj.outputFreq = 100;
            obj.audio = audioplayer(0,obj.sampling);
            
            % Initialize DAQ
            function startDAQ(~,~)
                try
                    obj.DAQ.s = daq.createSession('ni');
                    addAnalogInputChannel(obj.DAQ.s, 'Dev1', obj.channels, 'Voltage');
                    obj.DAQ.s.Rate = obj.sampling;
                    
                    obj.DAQ.ao = daq.createSession('ni');
                    addAnalogOutputChannel(obj.DAQ.ao, 'Dev1', 'ao0', 'Voltage');
                    obj.DAQ.ao.Rate = obj.outputFreq;
                    
                    obj.DAQ.s.IsContinuous = true;
                    obj.DAQ.ao.IsContinuous = false;
                    display('DAQ successfully initialized.')
                catch ex
                    display('Problem initializing DAQ!')
                end
            end
            startDAQ;
            
            % Initialize temporary file and file data
            function setFileLocation(~,~)
                c = clock;
                % get the folder location from the user
                obj.file.folder = [uigetdir(['C:\Data\PatchClamp\' num2str(c(1)) sprintf('%02d',c(2)) sprintf('%02d',c(3))]) '\'];
                % if unable to get input from user
                if isempty(obj.file.folder)
                    obj.file.folder = ['C:\Data\PatchClamp\' num2str(c(1)) sprintf('%02d',c(2)) sprintf('%02d',c(3)) '\'];
                end
                obj.file.prefix = [num2str(c(1)) '_' sprintf('%02d',c(2)) '_' sprintf('%02d',c(3))];
                obj.file.suffix = '.dbf';
                obj.file.num = 0;
                obj.file.name = [obj.file.folder obj.file.prefix '_' sprintf('%04d',obj.file.num) obj.file.suffix];
                obj.file.fid = [];
            end
            setFileLocation;
            
            % Create space for listeners
            obj.DAQ.listeners = [];
            
            % Define what happens on close
            function closeProg(~,~)
                % close figure
                delete(obj.fig)
                % delete stuff
                try
                    arrayfun(@(lh) delete(lh), obj.DAQ.listeners);
                    delete(obj.fig_cache);
                catch ex
                    
                end
                % end DAQ sessions
                try
                    stop(obj.DAQ.s);
                    stop(obj.DAQ.ao);
                    release(obj.DAQ.s);
                    release(obj.DAQ.ao);
                    delete(obj.DAQ);
                catch ex
                    
                end
                % delete the DataAcquistion object
                try
                    delete(obj);
                catch ex
                    
                end
            end
            
            % Create figure ===============================================
            
            % some UI defs
            obj.DEFS = [];
            obj.DEFS.BIGBUTTONSIZE  = 35;
            obj.DEFS.BUTTONSIZE     = 20;
            obj.DEFS.PADDING        = 2;
            obj.DEFS.LABELWIDTH     = 65;
            
            % start making GUI objects
            obj.fig = figure('Name','DataAcquisition','MenuBar','none',...
                'NumberTitle','off','DockControls','off','Visible','off', ...
                'DeleteFcn',@closeProg);
            
            % set its position
            oldunits = get(obj.fig,'Units');
            set(obj.fig,'Units','normalized');
            set(obj.fig,'Position',[0.1,0.1,0.8,0.8]);
            set(obj.fig,'Units',oldunits);
            
            % make the menu bar
            f = uimenu('Label','File');
            uimenu(f,'Label','Choose Save Location','Callback',@setFileLocation);
            uimenu(f,'Label','Normal acquisition','Callback',@(~,~) obj.normalMode);
            uimenu(f,'Label','IV curve','Callback',@(~,~) obj.ivMode);
            uimenu(f,'Label','Noise plot','Callback',@(~,~) obj.noiseMode);
            uimenu(f,'Label','Membrane seal test','Callback',@(~,~) obj.sealtestMode);
            uimenu(f,'Label','Quit','Callback',@closeProg);
            hm = uimenu('Label','Help');
            uimenu(hm,'Label','DataAcquisition','Callback',@(~,~) doc('DataAcquisition.m'));
            uimenu(hm,'Label','About','Callback',@(~,~) msgbox({'DataAcquisition v1.0 - written by Stephen Fleming.' '' ...
                'Created for Harvard''s 2016 Freshaman Seminar course 25o.' '' ...
                'This program and its author are not affiliated with National Instruments, Matlab, or Molecular Devices.' ''},'About DataAcquisition'));
            
            obj.mode = 'normal';
            obj.normalMode;
            
            % =============================================================
            
        end
        
        function normalMode(obj)
            % stop other things that might have been running
            obj.stopAll;
            obj.mode = 'normal';
            
            % set default positions
            obj.normalSizing;
            obj.normalResizeFcn;

            % Initialize figure cache
            obj.fig_cache = figure_cache(obj.axes, obj.alpha, 5);

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function normalSizing(obj)
            delete(obj.panel);
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);
            
            delete(obj.axes);
            obj.axes = axes('Parent',obj.panel,'Position',[0.05 0.05 0.95 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes,'NextPlot','add','XLimMode','manual');
            set(obj.axes,'XGrid','on','YGrid','on','Tag','Axes','Box','on');
            obj.axes.XLim = [0 5];
            obj.axes.YLim = [-1 1];
            obj.axes.YLabel.String = 'Current (pA)';
            obj.axes.YLabel.Color = 'k';
            obj.axes.XLabel.String = 'Time (s)';
            obj.axes.XLabel.Color = 'k';

            % now make the buttons

            % y-axis
            obj.ybuts = [];
            obj.ybuts(1) = uicontrol('Parent', obj.panel, 'String','<html>-</html>',...
                'callback', @(~,~) obj.fig_cache.zoom_y('out'));
            obj.ybuts(2) = uicontrol('Parent', obj.panel, 'String','<html>&darr;</html>',...
                'callback', @(~,~) obj.fig_cache.scroll_y('down'));
            obj.ybuts(3) = uicontrol('Parent', obj.panel, 'String','<html>R</html>',...
                'callback', @(~,~) obj.fig_cache.reset_fig);
            obj.ybuts(4) = uicontrol('Parent', obj.panel, 'String','<html>&uarr;</html>',...
                'callback', @(~,~) obj.fig_cache.scroll_y('up'));
            obj.ybuts(5) = uicontrol('Parent', obj.panel, 'String','<html>+</html>',...
                'callback', @(~,~) obj.fig_cache.zoom_y('in'));

            % x-axis
            obj.xbuts = [];
            obj.xbuts(1) = uicontrol('Parent', obj.panel, 'String','<html>-</html>',...
                'callback', @(~,~) obj.fig_cache.zoom_x('out'));
            obj.xbuts(2) = uicontrol('Parent', obj.panel, 'String','<html>+</html>',...
                'callback', @(~,~) obj.fig_cache.zoom_x('in'));

            % top
            obj.tbuts = [];
            obj.tbuts(1) = uicontrol('Parent', obj.panel, ...
                'Style', 'togglebutton', 'CData', imread('Record.png'),...
                'callback', @(src,~) obj.stateDecision(src), 'tag', 'record');
            obj.tbuts(2) = uicontrol('Parent', obj.panel, ...
                'Style', 'togglebutton', 'CData', imread('Play.png'),...
                'callback', @(src,~) obj.stateDecision(src), 'tag', 'play');

            % set the resize function
            set(obj.panel, 'ResizeFcn', @(~,~) obj.normalResizeFcn);
            % and call it to set default positions
            obj.normalResizeFcn;

            % Initialize figure cache
            obj.fig_cache = figure_cache(obj.axes, obj.alpha, 5);

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function normalResizeFcn(obj)
            % get size of panel in pixels
            sz = obj.getPixelPos(obj.panel);
            % position the axes object
            sz(1) = sz(1) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % left
            sz(3) = sz(3) - sz(1); % width
            sz(2) = sz(2) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % bottom
            sz(4) = sz(4) - sz(2) - obj.DEFS.BIGBUTTONSIZE - 3*obj.DEFS.PADDING; % height
            set(obj.axes,'Position',max(1,sz),'Units','Pixels');
            % get size of axes in pixels
            sz = obj.getPixelPos(obj.axes);
            % figure out where the y middle is
            mid = sz(4)/2 + sz(2);
            % position the buttons
            for i=1:numel(obj.ybuts)
                set(obj.ybuts(i),'Position',...
                    max(1,[obj.DEFS.PADDING, ...
                    mid+(i-numel(obj.ybuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]));
            end
            % figure out where the x middle is
            mid = sz(3)/2 + sz(1);
            % position the buttons
            for i=1:numel(obj.xbuts)
                set(obj.xbuts(i),'Position',...
                    max(1,[mid+(i-numel(obj.xbuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.PADDING, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]));
            end
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    max(1,[mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    sz(2) + sz(4) + obj.DEFS.PADDING, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]));
            end
        end

        function noiseMode(obj)
            % stop other things that might have been running
            obj.stopAll;
            obj.mode = 'noise';
            
            % set default positions
            obj.noiseSizing;
            obj.noiseResizeFcn;

            % No figure cache necessary
            obj.fig_cache = [];

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function noiseSizing(obj)
            delete(obj.panel);
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);
            
            delete(obj.axes);
            obj.axes = axes('Parent',obj.panel,'Position',[0.05 0.05 0.95 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes,'NextPlot','add','XLimMode','manual');
            set(obj.axes,'XGrid','on','YGrid','on','Tag','Axes', ...
                'Box','on','XScale','log','YScale','log');
            obj.axes.YLabel.String = 'Current noise power spectral density (nA^2/Hz)';
            obj.axes.YLabel.Color = 'k';
            obj.axes.XLabel.String = 'Frequency (Hz)';
            obj.axes.XLabel.Color = 'k';
            obj.axes.YLim = [1e-14, 1e-7];
            obj.axes.XLim = [1 3e4];

            % now make the buttons

            % y-axis
            obj.ybuts = [];
            obj.ybuts(1) = uicontrol('Parent', obj.panel, 'String','<html>-</html>',...
                'callback', @(~,~) zoom_y('out'));
            obj.ybuts(2) = uicontrol('Parent', obj.panel, 'String','<html>&darr;</html>',...
                'callback', @(~,~) scroll_y('down'));
            obj.ybuts(3) = uicontrol('Parent', obj.panel, 'String','<html>R</html>',...
                'callback', @(~,~) reset_fig);
            obj.ybuts(4) = uicontrol('Parent', obj.panel, 'String','<html>&uarr;</html>',...
                'callback', @(~,~) scroll_y('up'));
            obj.ybuts(5) = uicontrol('Parent', obj.panel, 'String','<html>+</html>',...
                'callback', @(~,~) zoom_y('in'));
            
            function zoom_y(str)
                if strcmp(str,'in')
                    obj.axes.YLim = 10.^(log10(get(obj.axes,'YLim')) + [1 -1]);
                elseif strcmp(str,'out')
                    obj.axes.YLim = 10.^(log10(get(obj.axes,'YLim')) + [-1 1]);
                end
            end
            
            function scroll_y(str)
                if strcmp(str,'up')
                    obj.axes.YLim = 10.^(log10(get(obj.axes,'YLim')) + [1 1]);
                elseif strcmp(str,'down')
                    obj.axes.YLim = 10.^(log10(get(obj.axes,'YLim')) + [-1 -1]);
                end
            end
            
            function reset_fig
                obj.axes.YLim = [1e-14, 1e-7];
                obj.axes.XLim = [1 3e4];
            end

            % top
            obj.tbuts = [];
            obj.tbuts(1) = uicontrol('Parent', obj.panel, ...
                'Style', 'togglebutton', 'CData', imread('Play.png'),...
                'callback', @(src,~) obj.stateDecision(src), 'tag', 'noise');

            % set the resize function
            set(obj.panel, 'ResizeFcn', @(~,~) obj.noiseResizeFcn);
            % and call it to set default positions
            obj.noiseResizeFcn;

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function noiseResizeFcn(obj)
            % get size of panel in pixels
            sz = obj.getPixelPos(obj.panel);
            % position the axes object
            sz(1) = sz(1) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % left
            sz(3) = sz(3) - sz(1); % width
            sz(2) = sz(2) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH; % bottom
            sz(4) = sz(4) - sz(2) - obj.DEFS.BIGBUTTONSIZE - 3*obj.DEFS.PADDING; % height
            set(obj.axes,'Position',max(1,sz),'Units','Pixels');
            % get size of axes in pixels
            sz = obj.getPixelPos(obj.axes);
            % figure out where the y middle is
            mid = sz(4)/2 + sz(2);
            % position the buttons
            for i=1:numel(obj.ybuts)
                set(obj.ybuts(i),'Position',...
                    max(1,[obj.DEFS.PADDING, ...
                    mid+(i-numel(obj.ybuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]));
            end
            % figure out where the x middle is
            mid = sz(3)/2 + sz(1);
            % position the buttons
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    max(1,[mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    sz(2) + sz(4) + obj.DEFS.PADDING, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]));
            end
        end
        
        function ivMode(obj)
            % stop other things that might have been running
            obj.stopAll;
            obj.mode = 'iv';
            
            % set default positions
            obj.ivSizing;
            obj.ivResizeFcn;

            % No figure cache necessary
            obj.fig_cache = [];

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function ivSizing(obj)
            delete(obj.panel);
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);
            
            delete(obj.axes);
            obj.axes(1) = axes('Parent',obj.panel,'Position',[0.05 0.05 0.45 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes(1),'NextPlot','add','XLimMode','manual');
            set(obj.axes(1),'XGrid','on','YGrid','on','Tag','Axes','Box','on');
            obj.axes(1).YLabel.String = 'Current (nA)';
            obj.axes(1).YLabel.Color = 'k';
            obj.axes(1).XLabel.String = 'Time (s)';
            obj.axes(1).XLabel.Color = 'k';
            obj.axes(1).YLim = [-0.5, 0.5];
            obj.axes(1).XLim = [0 0.5];
            
            obj.axes(2) = axes('Parent',obj.panel,'Position',[0.55 0.05 0.45 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes(2),'NextPlot','add','XLimMode','manual');
            set(obj.axes(2),'XGrid','on','YGrid','on','Tag','Axes','Box','on');
            obj.axes(2).YLabel.String = 'Mean Current (nA)';
            obj.axes(2).YLabel.Color = 'k';
            obj.axes(2).XLabel.String = 'Voltage (mV)';
            obj.axes(2).XLabel.Color = 'k';
            obj.axes(2).YLim = [-1 1];
            obj.axes(2).XLim = [-200 200];

            % now make the buttons

            % y-axis
            obj.ybuts = [];
            obj.ybuts(1) = uicontrol('Parent', obj.panel, 'String','<html>-</html>',...
                'callback', @(~,~) zoom_y('out'));
            obj.ybuts(2) = uicontrol('Parent', obj.panel, 'String','<html>&darr;</html>',...
                'callback', @(~,~) scroll_y('down'));
            obj.ybuts(3) = uicontrol('Parent', obj.panel, 'String','<html>R</html>',...
                'callback', @(~,~) reset_fig);
            obj.ybuts(4) = uicontrol('Parent', obj.panel, 'String','<html>&uarr;</html>',...
                'callback', @(~,~) scroll_y('up'));
            obj.ybuts(5) = uicontrol('Parent', obj.panel, 'String','<html>+</html>',...
                'callback', @(~,~) zoom_y('in'));
            
            function zoom_y(str)
                if strcmp(str,'in')
                    lims = 1/2*get(obj.axes(1),'YLim');
                elseif strcmp(str,'out')
                    lims = 2*get(obj.axes(1),'YLim');
                end
                obj.axes(1).YLim = lims;
                obj.axes(2).YLim = lims;
            end
            
            function scroll_y(str)
                if strcmp(str,'up')
                    lims = get(obj.axes(1),'YLim') + [1 1]*diff(get(obj.axes(1),'YLim'))/5;
                elseif strcmp(str,'down')
                    lims = get(obj.axes(1),'YLim') - [1 1]*diff(get(obj.axes(1),'YLim'))/5;
                end
                obj.axes(1).YLim = lims;
                obj.axes(2).YLim = lims;
            end
            
            function reset_fig
                obj.axes(1).YLim = [-1 1];
                obj.axes(2).YLim = [-1 1];
                obj.axes(1).XLim = [0 0.4];
            end

            % top
            obj.tbuts = [];
            obj.tbuts(1) = uicontrol('Parent', obj.panel, ...
                'Style', 'togglebutton', 'CData', imread('Play.png'),...
                'callback', @(src,~) obj.stateDecision(src), 'tag', 'iv');

            % set the resize function
            set(obj.panel, 'ResizeFcn', @(~,~) obj.ivResizeFcn);
            % and call it to set default positions
            obj.ivResizeFcn;

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function ivResizeFcn(obj)
            % position the axes1 object
            sz = obj.getPixelPos(obj.panel);
            sz(1) = sz(1) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % left
            sz(3) = sz(3)/2 - obj.DEFS.PADDING - 1.5*obj.DEFS.LABELWIDTH - obj.DEFS.BUTTONSIZE - 2*obj.DEFS.PADDING; % width
            sz(2) = sz(2) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH; % bottom
            sz(4) = sz(4) - sz(2) - obj.DEFS.BIGBUTTONSIZE - 3*obj.DEFS.PADDING; % height
            set(obj.axes(1),'Position',max(1,sz),'Units','Pixels');
            set(obj.axes(1),'Position',max(1,sz),'Units','Pixels');
            % figure out where the y middle is
            mid = sz(4)/2 + sz(2);
            % position the buttons
            for i=1:numel(obj.ybuts)
                set(obj.ybuts(i),'Position',...
                    [obj.DEFS.PADDING, ...
                    mid+(i-numel(obj.ybuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]);
            end
            % position the axes2 object
            sz = obj.getPixelPos(obj.panel);
            sz(1) = sz(1) + sz(3)/2 + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % left
            sz(3) = sz(3)/2 - obj.DEFS.PADDING - 1.5*obj.DEFS.LABELWIDTH - obj.DEFS.BUTTONSIZE - 2*obj.DEFS.PADDING; % width
            sz(2) = sz(2) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH; % bottom
            sz(4) = sz(4) - sz(2) - obj.DEFS.BIGBUTTONSIZE - 3*obj.DEFS.PADDING; % height
            set(obj.axes(2),'Position',max(1,sz),'Units','Pixels');
            % position the top button
            bottom = sz(2) + sz(4) + obj.DEFS.PADDING;
            sz = obj.getPixelPos(obj.panel);
            mid = sz(1)+sz(3)/2;
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    max(1,[mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    bottom, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]));
            end
        end
        
        function sealtestMode(obj)
            % stop other things that might have been running
            obj.stopAll;
            obj.mode = 'sealtest';
            
            % set default positions
            obj.sealtestSizing;
            obj.sealtestResizeFcn;

            % no figure cache
            obj.fig_cache = [];

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function sealtestSizing(obj)
            delete(obj.panel);
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);
            
            delete(obj.axes);
            obj.axes = axes('Parent',obj.panel,'Position',[0.05 0.05 0.95 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes,'NextPlot','replacechildren','XLimMode','manual');
            set(obj.axes,'XGrid','on','YGrid','on','Tag','Axes','Box','on');
            obj.axes.YLabel.String = 'Current (pA)';
            obj.axes.YLabel.Color = 'k';
            obj.axes.XLabel.String = 'Time (s)';
            obj.axes.XLabel.Color = 'k';
            obj.axes.YLim = [-100, 100];
            obj.axes.XLim = [0, 2/60];

            % now make the buttons

            % y-axis
            obj.ybuts = [];
            obj.ybuts(1) = uicontrol('Parent', obj.panel, 'String','<html>-</html>',...
                'callback', @(~,~) zoom_y('out'));
            obj.ybuts(2) = uicontrol('Parent', obj.panel, 'String','<html>&darr;</html>',...
                'callback', @(~,~) scroll_y('down'));
            obj.ybuts(3) = uicontrol('Parent', obj.panel, 'String','<html>R</html>',...
                'callback', @(~,~) reset_fig);
            obj.ybuts(4) = uicontrol('Parent', obj.panel, 'String','<html>&uarr;</html>',...
                'callback', @(~,~) scroll_y('up'));
            obj.ybuts(5) = uicontrol('Parent', obj.panel, 'String','<html>+</html>',...
                'callback', @(~,~) zoom_y('in'));
            
            function zoom_y(str)
                if strcmp(str,'in')
                    obj.axes.YLim = 1/2*get(obj.axes(1),'YLim');
                elseif strcmp(str,'out')
                    obj.axes.YLim = 2*get(obj.axes(1),'YLim');
                end
            end
            
            function scroll_y(str)
                if strcmp(str,'up')
                    obj.axes.YLim = get(obj.axes(1),'YLim') + [1 1]*diff(get(obj.axes(1),'YLim'))/5;
                elseif strcmp(str,'down')
                    obj.axes.YLim = get(obj.axes(1),'YLim') - [1 1]*diff(get(obj.axes(1),'YLim'))/5;
                end
            end
            
            function reset_fig
                obj.axes.YLim = [100, 100];
            end

            % top
            obj.tbuts = [];
            obj.tbuts(1) = uicontrol('Parent', obj.panel, ...
                'Style', 'togglebutton', 'CData', imread('Play.png'),...
                'callback', @(src,~) obj.stateDecision(src), 'tag', 'sealtest');

            % set the resize function
            set(obj.panel, 'ResizeFcn', @(~,~) obj.sealtestResizeFcn);
            % and call it to set default positions
            obj.sealtestResizeFcn;

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function sealtestResizeFcn(obj)
            % get size of panel in pixels
            sz = obj.getPixelPos(obj.panel);
            % position the axes object
            sz(1) = sz(1) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH + obj.DEFS.BUTTONSIZE; % left
            sz(3) = sz(3) - sz(1); % width
            sz(2) = sz(2) + obj.DEFS.PADDING + obj.DEFS.LABELWIDTH; % bottom
            sz(4) = sz(4) - sz(2) - obj.DEFS.BIGBUTTONSIZE - 3*obj.DEFS.PADDING; % height
            set(obj.axes,'Position',max(1,sz),'Units','Pixels');
            % get size of axes in pixels
            sz = obj.getPixelPos(obj.axes);
            % figure out where the y middle is
            mid = sz(4)/2 + sz(2);
            % position the buttons
            for i=1:numel(obj.ybuts)
                set(obj.ybuts(i),'Position',...
                    max(1,[obj.DEFS.PADDING, ...
                    mid+(i-numel(obj.ybuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]));
            end
            % figure out where the x middle is
            mid = sz(3)/2 + sz(1);
            % position the buttons
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    max(1,[mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    sz(2) + sz(4) + obj.DEFS.PADDING, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]));
            end
        end
        
        function writeFileHeader(obj, fid)
            % write a file header
            h.si = 1/obj.sampling;
            h.chNames = {'Current (pA)','Voltage (mV)'};
            h.data_compression_scaling = obj.data_compression_scaling;
            hh = getByteStreamFromArray(h);
            n = numel(hh);
            fwrite(fid,n,'*uint32');
            fwrite(fid,hh,'*uint8');
        end
        
        function writeFileData(obj, fid, data)
            fwrite(fid,int16(repmat(obj.data_compression_scaling,size(data,2),1)' .* data),'*int16');
        end
        
        function stateDecision(obj, src)
            % state machine for the main button presses
            if strcmp(get(src,'tag'),'play')
                button_state = get(src,'Value');
                if button_state == get(src,'Max')
                    % we are in play mode
                    recbutton = findobj(obj.tbuts,'tag','record');
                    obj.stopRecord(recbutton);
                    set(recbutton,'Value',0);
                    obj.play(src);
                else
                    % we are stopped
                    obj.stopPlay(src);
                end
            elseif strcmp(get(src,'tag'),'record')
                button_state = get(src,'Value');
                if button_state == get(src,'Max')
                    % we are in record mode
                    playbutton = findobj(obj.tbuts,'tag','play');
                    obj.stopPlay(playbutton);
                    set(playbutton,'Value',0);
                    obj.record(src);
                else
                    % we are stopped
                    obj.stopRecord(src);
                end
            elseif strcmp(get(src,'tag'),'noise')
                button_state = get(src,'Value');
                if button_state == get(src,'Max')
                    % we are in noise display mode
                    obj.startNoiseDisplay(src);
                else
                    % we are stopped
                    obj.stopNoiseDisplay(src);
                end
            elseif strcmp(get(src,'tag'),'iv')
                button_state = get(src,'Value');
                if button_state == get(src,'Max')
                    % we are in noise display mode
                    obj.startIV(src);
                else
                    % we are stopped
                    obj.stopIV(src);
                end
            elseif strcmp(get(src,'tag'),'sealtest')
                button_state = get(src,'Value');
                if button_state == get(src,'Max')
                    % we are in seal test mode
                    obj.startSealTest(src);
                else
                    % we are stopped
                    obj.stopSealTest(src);
                end
            end
        end
        
        function play(obj, button)
            % begins displaying data live from the DAQ
            try
                set(button,'CData',imread('Pause.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Pause');
            end
            try
                obj.fig_cache.clear_fig;
                % add listener for data
                obj.DAQ.listeners.plot = addlistener(obj.DAQ.s, 'DataAvailable', ...
                    @(~,event) obj.showData(event));
                % start DAQ session
                obj.DAQ.s.startBackground;
            catch ex
                display('Error.')
            end
        end
        
        function stopPlay(obj, button)
            % Data viewing off
            try
                set(button,'CData',imread('Play.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Play');
            end
            try
                obj.DAQ.s.stop;
                delete(obj.DAQ.listeners.plot);
            catch ex
                
            end
        end
        
        function record(obj, button)
            % begins displaying data live from the DAQ
            % and records it to a file in the designated save location
            try
                set(button,'CData',imread('Recording.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Recording!');
            end
            try
                obj.fig_cache.clear_fig;
                % make sure not to write over an existing file
                c = clock; % update date prefix
                prefix = [num2str(c(1)) '_' sprintf('%02d',c(2)) '_' sprintf('%02d',c(3))];
                % if there is a file with the same name in this folder
                num = obj.file.num;
                while ~isempty(ls([obj.file.folder prefix '_' sprintf('%04d',num) '*']))
                    num = num + 1; % increment the file number for the next file
                end
                % update the handle info
                obj.file.name = [obj.file.folder prefix '_' sprintf('%04d',num) obj.file.suffix];
                obj.file.prefix = prefix;
                obj.file.num = num;
                % get new file ready and open
                fid = fopen(obj.file.name,'w');
                obj.writeFileHeader(fid);
                % add listener for data
                obj.DAQ.listeners.logAndPlot = addlistener(obj.DAQ.s, 'DataAvailable', ...
                    @(~,event) obj.showDataAndRecord(event, fid));
                obj.file.fid = fid;
                display('Saving data to');
                display(obj.file.name);
                % start DAQ session
                obj.DAQ.s.startBackground;
            catch ex
                
            end
        end
        
        function stopRecord(obj, button)
            % Data viewing and recording off
            try
                set(button,'CData',imread('Record.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Record');
            end
            try
                fclose(obj.file.fid);
                obj.DAQ.s.stop;
                delete(obj.DAQ.listeners.logAndPlot);
            catch ex
                
            end
        end
        
        function showData(obj, evt)
            obj.fig_cache.update_cache([evt.TimeStamps, evt.Data]);
            obj.fig_cache.draw_fig_now();
        end
        
        function showDataAndRecord(obj, evt, fid)
            data = (repmat(obj.alpha,size(evt.Data,1),1) .* evt.Data)';
            obj.writeFileData(fid, data);
            obj.fig_cache.update_cache([evt.TimeStamps, evt.Data]);
            obj.fig_cache.draw_fig_now();
        end
        
        function startNoiseDisplay(obj, button)
            % Sample chunks of data, calculate noise, and display it
            try
                set(button,'CData',imread('Pause.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Pause');
            end
            try
                % add listener for data
                obj.DAQ.s.NotifyWhenDataAvailableExceeds = 2^16;
                obj.DAQ.listeners.noise = addlistener(obj.DAQ.s, 'DataAvailable', ...
                    @(~,event) obj.plotNoise(event));
                % start DAQ session
                obj.DAQ.s.startBackground;
            catch ex
                
            end
        end
        
        function stopNoiseDisplay(obj, button)
            try
                set(button,'CData',imread('Play.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Play');
            end
            try
                obj.DAQ.s.stop;
                obj.DAQ.s.IsNotifyWhenDataAvailableExceedsAuto = true; % set back to auto
                delete(obj.DAQ.listeners.noise);
            catch ex
                
            end
        end
        
        function plotNoise(obj, evt)
            % Calculate the noise power spectral density, and plot it
            % calculation
            fftsize = min(size(evt.Data,1),2^16);
            dfft = 1/obj.sampling*abs(fft(obj.alpha(1)/1000*evt.Data(:,1))).^2/fftsize; % fft!
            dfft = dfft(1:fftsize/2+1);
            dfft = 2*dfft;
            f = obj.sampling*(0:fftsize/2)/fftsize; % frequency range
            % plot
            cla(obj.axes);
            plot(obj.axes, f', dfft);
            drawnow;
        end
        
        function startIV(obj, button)
            % Current versus voltage curve
            % Apply -200:10:200mV for 200ms each (adjustable)
            % Plot data
            % Take the average current(voltage) and plot that as well
            try
                set(button,'CData',imread('Pause.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Stop');
            end
            try
                % get the desired sweep from user
                obj.DAQ.ao.IsContinuous = true;
                holdtime = 0.1; % in seconds, hold at 0mV before and after
                prompt = {'Starting voltage (mV):', ...
                    'Step by (mV):', ...
                    'Ending voltage (mV)', ...
                    'Duration of each voltage (ms):'};
                dlg_title = 'IV curve setup';
                defaultans = {'180','-10','-180','400'};
                answer = inputdlg(prompt,dlg_title,1,defaultans);
                if isempty(answer) % user pressed 'cancel'
                    obj.stopIV(button);
                    set(button,'Value',0);
                else % user entered an IV program
                    answer = str2double(answer);
                    V = linspace(answer(1),answer(3),(answer(3)-answer(1))/answer(2)+1)*0.001; % in Volts
                    t = answer(4)*0.001; % time in seconds

                    % program the output voltages
                    for i = 1:numel(V)-1
                        queueOutputData(obj.DAQ.ao,[zeros(1,obj.outputFreq*holdtime), ...
                            V(i)*ones(1,obj.outputFreq*t), ...
                            zeros(1,obj.outputFreq*holdtime)]'*obj.outputAlpha);
                    end
                    % there must be a bit extra to trigger last sweep
                    queueOutputData(obj.DAQ.ao,[zeros(1,obj.outputFreq*holdtime), ...
                            V(end)*ones(1,obj.outputFreq*t), ...
                            zeros(1,obj.outputFreq*holdtime+5)]'*obj.outputAlpha);

                    % make sure not to write over an existing file
                    c = clock; % update date prefix
                    prefix = [num2str(c(1)) '_' sprintf('%02d',c(2)) '_' sprintf('%02d',c(3))];
                    % if there is a file with the same name in this folder
                    num = obj.file.num;
                    while ~isempty(ls([obj.file.folder prefix '_' sprintf('%04d',num) '*']))
                        num = num + 1; % increment the file number for the next file
                    end
                    % update the handle info
                    obj.file.name = [obj.file.folder prefix '_' sprintf('%04d',num) '_IV' obj.file.suffix];
                    obj.file.prefix = prefix;
                    obj.file.num = num;
                    % get new file ready and open
                    obj.file.fid = fopen(obj.file.name,'w');
                    obj.writeFileHeader(obj.file.fid);
                    display('Saving data to');
                    display(obj.file.name);

                    % how to plot
                    obj.DAQ.s.NotifyWhenDataAvailableExceeds = 2*obj.sampling*holdtime + obj.sampling*t; % points in each sweep
                    obj.DAQ.listeners.IVsweep = addlistener(obj.DAQ.s, 'DataAvailable', ...
                        @(~,event) obj.plotIV(event, holdtime, 2*holdtime+t, obj.file.fid));
                    cla(obj.axes(1));
                    obj.axes(1).YLim = [-2*max(V), 2*max(V)];
                    obj.axes(2).YLim = [-2*max(V), 2*max(V)];
                    obj.axes(1).XLim = [0, 2*holdtime+t];
                    cla(obj.axes(2));

                    % start DAQ session
                    obj.DAQ.ao.startBackground;
                    obj.DAQ.s.startBackground;

                    % wait until done and then kill it
                    pause(numel(V)*(2*holdtime+t+0.01)); % THIS IS BAD... NEED EVENT
                    set(button,'Value',0);
                    obj.stopIV(button);
                end
            catch ex
                
            end
        end
        
        function stopIV(obj, button)
            % stop the IV curve stuff
            try
                set(button,'CData',imread('Play.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Start');
            end
            try
                fclose(obj.file.fid);
                obj.DAQ.s.stop;
                obj.DAQ.ao.stop;
                obj.DAQ.ao.IsContinuous = false;
                delete(obj.DAQ.listeners.IVsweep);
            catch ex
                
            end
        end
        
        function plotIV(obj, evt, holdtime, sweeptime, fid)
            % when a full sweep of data comes in, this event fires
            % plots the sweep on axis 1
            % plots a mean data point on axis 2
            
            % save the data to a file
            data = (repmat(obj.alpha,size(evt.Data,1),1) .* evt.Data)';
            obj.writeFileData(fid, data);
            
            % plot the data
            plot(obj.axes(1), linspace(0,sweeptime,size(evt.Data,1)), evt.Data(:,1)*obj.alpha(1)/1000, 'Color', 'k');
            measuretime = sweeptime-2*holdtime;
            inds = round(((holdtime+measuretime/5):(holdtime+4*measuretime/5))*obj.sampling);
            voltage = mean(evt.Data(inds,2)*obj.alpha(2)); % mV
            current = mean(evt.Data(inds,1)*obj.alpha(1)/1000);
            plot(obj.axes(2), voltage, current, 'ok');
        end
        
        function startSealTest(obj, button)
            % Membrane "seal test" display
            % Apply a 5mV square wave
            % Measure current
            % Display as would an oscilloscope on a trigger
            obj.DAQ.ao.IsContinuous = true;
            v = 0.005; % 5mV
            ontime = 0.01; % time of pulse, sec
            rest = 0.1; % time of rest, sec
            onpts = round(ontime*obj.outputFreq);
            offpts = rest*obj.outputFreq;
            try
                set(button,'CData',imread('Pause.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Stop');
            end
            try
                % program the output voltages to go on indefinitely
                sig = [zeros(1,round(offpts/2)), ...
                    v*ones(1,onpts), ...
                    zeros(1,round(offpts/2))]'*obj.outputAlpha;
                queueOutputData(obj.DAQ.ao,repmat(sig,100,1));
                obj.DAQ.listeners.sealtestV = addlistener(obj.DAQ.ao, ...
                    'DataRequired', @(~,~) queueOutputData(obj.DAQ.ao,repmat(sig,100,1)));
                
                % how to plot
                obj.DAQ.s.NotifyWhenDataAvailableExceeds = obj.sampling/100*(onpts+offpts); % points in each sweep
                obj.DAQ.listeners.sealtest = addlistener(obj.DAQ.s, 'DataAvailable', ...
                    @(~,event) obj.plotSealTest(event, (onpts+offpts)/100));
                plot(obj.axes,linspace(-onpts/100,2*onpts/100,100),zeros(1,100))
                obj.axes.XLim = [-onpts 2*onpts]/100;
                
                % start DAQ session
                obj.DAQ.ao.startBackground;
                obj.DAQ.s.startBackground;
            catch ex
                display('Seal test issue')
            end
        end
        
        function stopSealTest(obj, button)
            % stop the seal test
            try
                set(button,'CData',imread('Play.png'));
                set(button,'String','');
            catch ex
                set(button,'String','Start');
            end
            try
                obj.DAQ.s.stop;
                obj.DAQ.ao.stop;
                obj.DAQ.ao.IsContinuous = false;
                delete(obj.DAQ.listeners.sealtest);
                delete(obj.DAQ.listeners.sealtestV);
            catch ex
                
            end
        end
        
        function plotSealTest(obj, evt, duration)
            % Plot data from the seal test function
            try
                vmax = max(evt.Data(:,2)*obj.alpha(2));
                voffpt = find(evt.Data(:,2)*obj.alpha(2)<vmax/3,1,'first');
                offset = find(evt.Data(voffpt:end,2)*obj.alpha(2)>vmax/2,1,'first');
                starttime = -offset/obj.sampling;
                if ~isempty(starttime)
                    x = linspace(starttime,starttime+duration,size(evt.Data,1));
                    set(obj.axes.Children,'XData',x,'YData',evt.Data(:,1)*obj.alpha(1)); % advanced play
                end
            catch ex
                display('Difficulty plotting seal test data')
            end
            % Play sound
%             try
%                 if strcmp(obj.audio.Running,'off')
%                     t = 0:1e-3:1*duration;
%                     f = exp(abs(mean(evt.Data(:,1)))*1000);
%                     if f>20
%                         f = 100;
%                     end
%                     y = square(2*pi*f*t,50)+randn(size(t))/10;
%                     obj.audio = audioplayer(y,1000);
%                     play(obj.audio);
%                 end
%             catch ex
%                 display('Could not play sound')
%             end
        end
        
        function stopAll(obj)
            % stops all DAQ sessions and deletes all listeners
            try
                obj.stopNoiseDisplay([]);
            catch ex
                
            end
            try
                obj.stopPlay([]);
            catch ex
                
            end
            try
                obj.stopRecord([]);
            catch ex
                
            end
            try
                obj.stopIV([]);
            catch ex
                
            end
            try
                obj.stopSealTest([]);
            catch ex
                
            end
        end
        
        function sz = getPixelPos(~, hnd)
            old_units = get(hnd,'Units');
            set(hnd,'Units','Pixels');
            sz = get(hnd,'Position');
            set(hnd,'Units',old_units);
        end
        
        function in = parseInputs(obj, varargin)
            try
                % use inputParser to figure out all the inputs
                p = inputParser;
                varargin = varargin{:};

                % defaults and checks
                defaultSampleFreq = 25000;
                checkSampleFreq = @(x) all([isnumeric(x), numel(x)==1, x>=10, x<=50000]);
                defaultChannels = [0, 1];
                checkChannels = @(x) all([isnumeric(x), arrayfun(@(y) y>=1, x), ...
                    arrayfun(@(y) y<=4, x), numel(unique(x))==numel(x), ...
                    numel(x)>0, numel(x)<=4]);
                defaultAlpha = [100, 100];
                checkAlpha = @(x) all([isnumeric(x), arrayfun(@(y) y>0, x), ...
                    numel(x)>0, numel(x)<=4]);
                defaultOutputAlpha = 10;
                checkOutputAlpha = @(x) all([isnumeric(x), numel(x)==1, x>0]);
                
                % set up the inputs
                if any(cellfun(@(x) strcmp(x,'Channels'), varargin))
                    % if the number of channels is specified
                    logic = cellfun(@(x) strcmp(x,'Channels'), varargin);
                    ind = find(logic,1,'first'); % which index is the input 'Channels'
                    chan = varargin{ind+1}; % vector of channels
                    checkAlpha = @(x) all([isnumeric(x), arrayfun(@(y) y>0, x), numel(x)==numel(chan)]);
                    % you are required to specify each alpha (channel conversion factor)
                    addRequired(p,'Alphas',defaultAlpha,checkAlpha);
                    % also redefine the sample frequency check
                    checkSampleFreq = @(x) all([isnumeric(x),x>=10,x<=floor(100000/numel(chan))]);
                else
                    % assume number of channels equal to numel(alpha)
                    logic = cellfun(@(x) strcmp(x,'Alphas'), varargin);
                    if sum(logic)>0
                        ind = find(logic,1,'first'); % which index is the input 'Channels'
                        alphas = varargin{ind+1}; % vector of alphas
                        defaultChannels = 0:1:numel(alphas);
                    end
                    addOptional(p,'Alphas',defaultAlpha,checkAlpha);
                end
                addOptional(p,'SampleFrequency',defaultSampleFreq,checkSampleFreq);
                addOptional(p,'Channels',defaultChannels,checkChannels);
                addOptional(p,'OutputAlpha',defaultOutputAlpha,checkOutputAlpha);
                
                % parse
                parse(p,varargin{:});
                in = p.Results;
            catch ex
                display('Invalid inputs to DataAcquisition.')
                display('Valid name/value pair designations are:')
                display('''SampleFrequency''')
                display('''Channels''')
                display('''Alphas''')
                display('''OutputAlpha''')
                display('''Channels'' is a maximum 4 element vector containing the integers 0 through 3.  E.g. [0, 1]')
                display('Keep in mind that if you specify channels, you must specify the value of alpha for each of those channels.')
                display('Example of a valid call: >> DataAcquisition(''Channels'',[0,1],''Alphas'',[0.1,1])')
            end
        end
        
    end
    
end