classdef DataAcquisition < handle
% DATAACQUISITION is a Matlab program for electronic signal acquistion from
% an NI-DAQ USB 6003.

% Stephen Fleming 2016.08.13

    properties
        fig         % Handle for the entire DataAcquisition figure
        DAQ         % Matlab DAQ object handle
        file        % Information about the next data file to be saved
        mode        % Which program is running: normal, noise, iv
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
    end

    methods (Hidden=true)
        
        function obj = DataAcquisition()
            % Constructor
            
            function startDAQ(~,~)
                % Initialize DAQ
                try
                    obj.DAQ.s = daq.createSession('ni');
                    addAnalogInputChannel(obj.DAQ.s, 'Dev1', 0:1, 'Voltage');
                    obj.DAQ.s.Rate = 30000;
                    
                    obj.DAQ.ao = daq.createSession('ni');
                    addAnalogOutputChannel(obj.DAQ.ao, 'Dev1', 'ao0', 'Voltage');
                    obj.DAQ.ao.Rate = 100;
                    queueOutputData(obj.DAQ.ao, zeros(100,1));
                    
                    obj.DAQ.s.IsContinuous = true;
                    obj.DAQ.ao.IsContinuous = true;
                    display('DAQ successfully initialized.')
                catch ex
                    display('Problem initializing DAQ!')
                    disp(daq.getDevices);
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
                obj.file.suffix = '.bin';
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
                    delete(obj.DAQ);
                catch ex
                    
                end
            end
            
            % Create figure ===============================================
            
            % some UI defs
            obj.DEFS = [];
            obj.DEFS.BIGBUTTONSIZE  = 35;
            obj.DEFS.BUTTONSIZE     = 20;
            obj.DEFS.PADDING        = 2;
            obj.DEFS.LABELWIDTH     = 55;
            
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
            uimenu(f,'Label','Live noise plot','Callback',@(~,~) obj.noiseMode);
            uimenu(f,'Label','Quit','Callback',@closeProg);
            hm = uimenu('Label','Help');
            uimenu(hm,'Label','DataAcquisition','Callback',@(~,~) doc('DataAcquisition.m'));
            uimenu(hm,'Label','About','Callback',@(~,~) msgbox({'DataAcquisition v1.0 - written by Stephen Fleming, 2016.' '' ...
                'This program and its author are not affiliated with National Instruments, Matlab, or Molecular Devices.' ''},'About DataAcquisition'));
            
            obj.mode = 'normal';
            obj.normalMode;
            
            % =============================================================
            
        end
        
        function normalMode(obj)
            % stop other things that might have been running
            try
                obj.stopNoiseDisplay([]);
            catch ex
                
            end
            
            % set default positions
            obj.normalSizing;
            obj.normalResizeFcn;

            % Initialize figure cache
            obj.fig_cache = figure_cache(obj.axes, 2, 5);

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function normalSizing(obj)
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);

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
            obj.fig_cache = figure_cache(obj.panel, 2, 5);

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
            set(obj.axes,'Position',sz,'Units','Pixels');
            % get size of axes in pixels
            sz = obj.getPixelPos(obj.axes);
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
            % figure out where the x middle is
            mid = sz(3)/2 + sz(1);
            % position the buttons
            for i=1:numel(obj.xbuts)
                set(obj.xbuts(i),'Position',...
                    [mid+(i-numel(obj.xbuts)/2-1)*obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.PADDING, ...
                    obj.DEFS.BUTTONSIZE, ...
                    obj.DEFS.BUTTONSIZE]);
            end
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    [mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    sz(2) + sz(4) + obj.DEFS.PADDING, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]);
            end
        end

        function noiseMode(obj)
            % stop other things that might have been running
            try
                obj.stopPlay([]);
            catch ex
                
            end
            try
                obj.stopRecord([]);
            catch ex
                
            end
            
            % set default positions
            obj.noiseSizing;
            obj.noiseResizeFcn;

            % No figure cache necessary
            obj.fig_cache = [];

            % Show figure
            obj.fig.Visible = 'on';

        end
        
        function noiseSizing(obj)
            obj.panel = uipanel('Parent',obj.fig,'Position',[0 0 1 1]);

            obj.axes = axes('Parent',obj.panel,'Position',[0.05 0.05 0.95 0.90],...
                'GridLineStyle','-','XColor', 0.15*[1 1 1],'YColor', 0.15*[1 1 1]);
            set(obj.axes,'NextPlot','add','XLimMode','manual');
            set(obj.axes,'XGrid','on','YGrid','on','Tag','Axes', ...
                'Box','on','XScale','log','YScale','log');
            obj.axes.YLabel.String = 'Current noise power spectral density (nA^2/Hz)';
            obj.axes.YLabel.Color = 'k';
            obj.axes.XLabel.String = 'Frequency (Hz)';
            obj.axes.XLabel.Color = 'k';
            obj.axes.YLim = [1e-12, 1e-4];
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
                obj.axes.YLim = [1e-12, 1e-4];
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
            set(obj.axes,'Position',sz,'Units','Pixels');
            % get size of axes in pixels
            sz = obj.getPixelPos(obj.axes);
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
            % figure out where the x middle is
            mid = sz(3)/2 + sz(1);
            % position the buttons
            for i=1:numel(obj.tbuts)
                set(obj.tbuts(i),'Position',...
                    [mid+(i-numel(obj.tbuts)/2-1)*obj.DEFS.BIGBUTTONSIZE, ...
                    sz(2) + sz(4) + obj.DEFS.PADDING, ...
                    obj.DEFS.BIGBUTTONSIZE, ...
                    obj.DEFS.BIGBUTTONSIZE]);
            end
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
                while ~isempty(ls([obj.file.folder prefix '_' sprintf('%04d',num) obj.file.suffix]))
                    num = num + 1; % increment the file number for the next file
                end
                % update the handle info
                obj.file.name = [obj.file.folder prefix '_' sprintf('%04d',num) obj.file.suffix];
                obj.file.prefix = prefix;
                obj.file.num = num;
                % get new file ready and open
                fid = fopen(obj.file.name,'w');
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
        
        function showData(obj, evt)
            obj.fig_cache.update_cache([evt.TimeStamps, evt.Data]);
            obj.fig_cache.draw_fig_now();
        end
        
        function showDataAndRecord(obj, evt, fid)
            data = [evt.TimeStamps, evt.Data]' ;
            fwrite(fid,data,'double');
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
            sfreq = 30000;
            fftsize = min(size(evt.Data,1),2^16);
            dfft = sfreq*abs(fft(evt.Data(:,2))).^2/fftsize;
            dfft = dfft(1:fftsize/2+1);
            dfft = 2*dfft;
            f = sfreq*(0:fftsize/2)/fftsize; % frequency range
            % plot
            cla(obj.axes);
            plot(obj.axes, f', dfft);
            drawnow;
        end
        
        function sz = getPixelPos(~, hnd)
            old_units = get(hnd,'Units');
            set(hnd,'Units','Pixels');
            sz = get(hnd,'Position');
            set(hnd,'Units',old_units);
        end
        
    end
    
end