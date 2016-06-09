classdef figure_cache < handle
    % A figure_cache is an object which stores the information to be
    % displayed in a figure that is constantly being updated.
    % Stephen Fleming 2016/06/08
    
    properties
        nsigs = 2; % number of channels being displayed
        xmax = 5; % maximum limit of x axis (time in seconds)
        pts = 5000; % total number of points displayed
        xdata = linspace(0,5,5000)';
        ydata = nan(5000,2);
        buffer = 5000/20; % blank space ahead of data
        ax; % axis object that this figure_cache object is attached to
        cmap = get(groot,'defaultaxescolororder');
    end
    
    methods
        
        function obj = figure_cache(ax, nsigs, xm)
            % constructor
            obj.ax = ax;
            obj.nsigs = nsigs;
            obj.xmax = xm;
            obj.xdata = linspace(0,xm,obj.pts)';
            obj.ydata = nan(obj.pts,nsigs);
        end
        
        function clear_fig(obj)
            % draws initial non-data on figure
            % plot so it's not an empty axis object
            % or to clear data from axes
            obj.ydata = nan(obj.pts,obj.nsigs);
            plot(obj.ax, obj.xdata, obj.ydata);
            obj.ax;
            xlim([0 obj.xmax]);
            xlabel('Time (s)');
            ylabel('Current (pA)')
            grid(obj.ax,'on');
            grid(obj.ax,'minor');
        end
        
        function update_cache(obj, newdata)
            % updates the data in the cache with new data
            % 'newdata' should be in column form, x being column 1
            try
                data = obj.downsample_random(newdata);
                try
                    firstpt = max(1, round(mod(data(1,1),obj.xmax)/obj.xmax*obj.pts));
                    lastpt = min(obj.pts, firstpt+size(data,1)-1);
                    obj.ydata(firstpt:lastpt,1:obj.nsigs) = data((firstpt:lastpt)-firstpt+1,2:obj.nsigs+1); % new data
                    obj.ydata(lastpt:min(obj.pts,lastpt+obj.buffer),1:obj.nsigs) = nan; % buffer
                catch ex
                   display('Wrong number of input signals.');
                end
            catch ex
                display('Problem downsampling data.');
            end
        end
        
        function draw_fig_now(obj)
            % draws the data currently in the cache
            try
                % get axis object on DataAcquisition GUI
                %logic = boolean(arrayfun(@(x) isa(x,'matlab.graphics.axis.Axes'), obj.ax.Children));
                u = obj.ax.Children;
                if isempty(u)
                    plot(obj.ax, obj.xdata,obj.ydata);
                else
                    for i = 1:obj.nsigs
                        set(u(i),'YData',obj.ydata(:,i),'Color',obj.cmap(i,:)); % advanced play
                    end
                end
                drawnow;
            catch ex
                display('Trouble updating plot.');
            end
        end
        
    end
    
    methods (Access = private)
        
        function d = downsample_minmax(obj, data)
            % downsamples data appropriately for viewing on a plot
            dspoints = (data(end,1)-data(1,1))/obj.xmax*obj.pts; % number of points in the plot
            if dspoints > 0.25*size(data,1) % there's no point in downsampling in this way
                d = obj.downsample_random(data);
                return;
            end
            d = nan(dspoints,size(data,2)-1);
            for i = 1:(size(data,2)-1)
                d1 = accumarray(ceil(linspace(1,round(dspoints/2),size(data,1)))',data(:,2:end),[],@max)';
                d2 = accumarray(ceil(linspace(1,round(dspoints/2),size(data,1)))',data(:,2:end),[],@min)';
                d(:,i) = reshape([d1; d2],[1, numel(d1)+numel(d2)]);
            end
        end
        
        function d = downsample_random(obj, data)
            % downsamples data appropriately for viewing on a plot
            dspoints = round((data(end,1)-data(1,1))/obj.xmax*obj.pts); % number of points in the plot
            logic = [ones(1,dspoints), zeros(1,size(data,1)-dspoints)]; % dspoints number of ones
            logic = boolean(logic(:,randperm(size(logic,2)))); % random rearrangement
            d = data(logic',:);
        end
        
    end
    
end
        