function plotData(src, evt, fig_cache)
% Add the time stamp and the data values to data.
% Stephen Fleming, 2016/06/09

    fig_cache.update_cache([evt.TimeStamps, evt.Data]);
    fig_cache.draw_fig_now();

end