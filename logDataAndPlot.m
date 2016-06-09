function logDataAndPlot(src, evt, fid, fig_cache)
% Add the time stamp and the data values to data.
% Stephen Fleming, 2016/06/08

    logData(src, evt, fid);
    
    fig_cache.update_cache([evt.TimeStamps, evt.Data]);
    fig_cache.draw_fig_now();

end