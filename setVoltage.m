function setVoltage(src, values, varargin)
% Set voltages and hold indefinitely.
% 'values' is a row vector of voltages in Volts.
% 'varargin' is intended to contain a length of time (s), after which the
% voltages are set to zero.
% Stephen Fleming, 2016/06/08

    if numel(varargin)>0
        num = varargin{1}*src.Rate;
        queueOutputData(src, [ones(num,1); 0]*values);
    else
        num = src.Rate/2; % minimum number of samples to queue
        queueOutputData(src, ones(num,1)*values);
    end
    
end