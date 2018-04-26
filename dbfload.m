function [ d, h ] = dbfload(filename, range, format)
    % DBFLOAD Loads data from a DataAcquisition-generated file in a range of
    % indices.
    %
    %   [d,h] = dbfload(filename, range, format) - Load range=[start,end] of points, 0-based
    %   [~,h] = dbfload(filename, 'info') - Load header data only
    %
    % calling dbfload(filename) without specifying a range will return the
    % full dataset
    % (... this could be a bad idea depending on the file size ...)
    %
    % 'format' is supposed to be 'double' or 'int16'
    %
    % DBFLOAD is called by DataAcquisition and used as a file converter.
    % That is the recommended usage.
    %
    % Stephen Fleming
    
    d = [];
    h = [];

    % open the file and read header
    fid = fopen(filename,'r');
    if fid == -1
        error(['Could not open ' filename]);
    end
    
    % get total length of file
    fileinfo = dir(filename);
    fileSize = fileinfo.bytes;
    
    % now read number of header points, and the header
    nh = uint64(fread(fid,1,'*uint32'));
    hh = fread(fid,nh,'*uint8');
    h = getArrayFromByteStream(hh);
    
    fstart = 4+nh;
    bytesize = 2; % int16
    
    % also, how many points and channels?
    h.numChan = numel(h.chNames);
    % this is the total number of points
    h.numTotal = double(fileSize - fstart)/bytesize;
    % this is the number per each channel
    h.numPts = double(h.numTotal/h.numChan);
    
    % load data, or just return header?
    if nargin > 1 && strcmp(range,'info')
        fclose(fid);
        return;
    end
    
    % find the right place to seek, and do so
    if nargin<2
        range = [0 h.numPts];
    end

    % go to start
    fseek(fid, fstart+range(1)*bytesize*h.numChan, 'bof'); % double needs an 8 here
    % how many points and array size
    npts = range(2) - range(1);
    sz = [h.numChan, npts];
    % now read
    d16 = fread(fid, sz, '*int16')';
    
    % abort if the data file is empty
    if isempty(d16)
        error('dbfload:fileEmpty','Data file is empty.')
    end
    
    % decide how to output data
    if nargin > 2 && strcmp(format,'int16')
        % keep data as 16-bit integers
        d = d16;
    else
        % scale data from 16-bit integer to a double
        %d = double(d16)./repmat(h.data_compression_scaling,size(d16,1),1);
        d = double(d16) / h.data_compression_scaling;
    end

    % all done
    fclose(fid);
end

