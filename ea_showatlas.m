function [atlases,colorbuttons,atlassurfs,atlaslabels] = ea_showatlas(varargin)
% This function shows atlas data in the 3D-Scene viewer. It
% reads in all atlases found in the eAuto_root/atlases folder, calculates a
% convex hull around the nonzero area and renders this area as 3D surfaces.
% For a small part of contact statistics, the function uses
% inhull.m which is covered by the BSD-license (see below).
% __________________________________________________________________________________
% Copyright (C) 2014 Charite University Medicine Berlin, Movement Disorders Unit
% Andreas Horn

resultfig=varargin{1};
if nargin==2
    options=varargin{2};
end
if nargin>2
    elstruct=varargin{2};
    options=varargin{3};
end

nm=1:2; % native and mni
try
    nmind=[options.atl.can,options.atl.ptnative]; % which shall be performed?
catch
    nmind=[1 0];
end
nm=nm(logical(nmind)); % select which shall be performed.

for nativemni=nm % switch between native and mni space atlases.

    switch nativemni
        case 1
            adir=[ea_space(options,'atlases'),options.atlasset,filesep];
            mifix='';
        case 2
            adir=[[options.root,options.patientname,filesep],'atlases',filesep,options.atlasset,filesep];
            mifix='';
    end

    atlascnt=1;
    set(0,'CurrentFigure',resultfig)

    if ~exist([adir,'atlas_index.mat'],'file')
        atlases=ea_genatlastable([],ea_space(options,'atlases'),options,mifix);
    else
        load([adir,'atlas_index.mat']);
        atlases=ea_genatlastable(atlases,ea_space(options,'atlases'),options,mifix);
    end

    isdiscfibers = cellfun(@(x) ischar(x) && strcmp(x, 'discfibers'), atlases.pixdim);
    if all(sum(isdiscfibers,2))
        atlases.discfibersonly = 1;
    else
        atlases.discfibersonly = 0;
    end

    if options.writeoutstats
        try
            load([options.root,options.patientname,filesep,'ea_stats']);
            prioratlasnames=ea_stats.atlases.names;
        end
    end

    if ~isfield(atlases,'defaultset')
        atlases.defaultset=1; % show all structures.
    end

    if isfield(atlases,'colormap')
        try
            jetlist=eval(atlases.colormap);
        catch
            jetlist=atlases.colormap;
        end
        %colormap(atlases.colormap);
    else
        try
            jetlist=options.colormap;
            atlases.colormap=jetlist;
            colormap(jetlist)
        catch
            atlases.colormap='jet';
            jetlist=jet;
        end
    end

    setinterpol=1;

    ht=getappdata(resultfig,'atlht');
    if ~isempty(ht) % sweep nonempty atlases toolbar
        delete(ht.Children(:));
    else
        ht=uitoolbar(resultfig);
    end

    if ~atlases.discfibersonly
        atlcntbutton=uipushtool(ht,'CData',ea_get_icn('atlases'),'Tag','Atlas Control','TooltipString','Atlas Control Figure','ClickedCallback',{@ea_openatlascontrol,atlases,resultfig,options});
    end

    % prepare stats fields
    if options.writeoutstats
        for el=1:length(elstruct)
            for side=1:length(elstruct(el).coords_mm)
                ea_stats.conmat{el,side}=nan(size(elstruct(el).coords_mm{side},1),length(atlases.names));
                ea_stats.conmat_inside_vox{el,side}=nan(size(elstruct(el).coords_mm{side},1),length(atlases.names));
                ea_stats.conmat_inside_hull{el,side}=nan(size(elstruct(el).coords_mm{side},1),length(atlases.names));
                ea_stats.patname{el,side}=elstruct(el).name;
            end
        end
        ea_stats.atlases.names=atlases.names; % only save basic atlases information.
        ea_stats.atlases.types=atlases.types; % only save basic atlases information.
        ea_stats.electrodes=elstruct;
    end

    % iterate through atlases, visualize them and write out stats.
    for atlas=1:length(atlases.names)
        [~,sidestr]=detsides(atlases.types(atlas));
        for side=detsides(atlases.types(atlas))
            if isnumeric(atlases.pixdim{atlas,side}) || strcmp(atlases.pixdim{atlas,side}, 'fibers')
                fv=atlases.fv{atlas,side};

                if ischar(options.prefs.hullsimplify)   % for 'auto' hullsimplify
                    % get to 700 faces
                    simplify=700/length(fv.faces);
                    if simplify < 1 % skip volumes with fewer than 700 faces
                        fv=reducepatch(fv,simplify);
                    end
                else
                    if options.prefs.hullsimplify<1 && options.prefs.hullsimplify>0
                        fv=reducepatch(fv,options.prefs.hullsimplify);
                    elseif options.prefs.hullsimplify>1
                        simplify=options.prefs.hullsimplify/length(fv.faces);
                        fv=reducepatch(fv,simplify);
                    end
                end

                rndfactor=1;
                try
                    switch atlases.names{atlas,side}(end-2:end)
                        case 'nii'
                            rndfactor=2;
                        case {'trk','mat'}
                            rndfactor=0.2;
                    end
                end

                try
                    if ~options.prefs.d3.colorjitter
                        rndfactor=0;
                    end
                end

                cdat=repmat(atlases.colors(atlas),length(fv.vertices),1); % C-Data for surface

                if size(cdat,2)==1
                    if any(round(cdat)==0) % rounding error for large atlases.
                        cdat(round(cdat)==0)=1;
                    end
                    cdat=atlases.colormap(round(cdat),:);
                end

                % add color jitter
                cdat=cdat+(randn(size(cdat,1),3)*rndfactor);

                XYZ=atlases.XYZ{atlas,side};
                pixdim=atlases.pixdim{atlas,side};
                colorc=nan;

                % show atlas label

                if size(XYZ.mm,1)>1 % exception for single-coordinate atlases...
                    try
                        [~,centroid]=kmeans(XYZ.mm(:,1:3),1);
                    catch
                        centroid=mean(XYZ.mm(:,1:3),1);
                    end
                else
                    try
                        centroid=XYZ.mm(:,1:3);
                    catch
                        centroid=[0,0,0];
                        warning('No centroid found.')
                    end
                end
                try
                    centroid=centroid(1,:);
                catch % empty file..
                    break
                end

                set(0,'CurrentFigure',resultfig);

                visible='on';
                if isfield(atlases,'presets')
                    if ~ismember(atlas,atlases.presets(atlases.defaultset).show)
                        visible='off';
                    end
                end
                if ~(atlases.types(atlas)>5)
                    atlassurfs(atlascnt,1)=patch(fv,'FaceVertexCData',cdat,'FaceColor','interp','facealpha',0.7,'EdgeColor','none','facelighting','phong','visible',visible);
                end
                % export label and labelbutton

                [~,thislabel]=fileparts(atlases.names{atlas});
                % try % use try here because filename might be shorter than .nii
                %     if strcmp(thislabel(end-3:end),'.nii') % if it was .nii.gz, fileparts will only remove .gz
                        [~,thislabel]=fileparts(thislabel);
                %     end
                % end
                atlaslabels(atlas,side)=text(double(centroid(1)),double(centroid(2)),double(centroid(3)),ea_sub2space(thislabel),'Tag',[thislabel,'_',sidestr{side}],'VerticalAlignment','Baseline','HorizontalAlignment','Center','Color','w');

                if ~exist('labelbutton','var')
                    labelbutton=uitoggletool(ht,'CData',ea_get_icn('labels'),'Tag','Labels','TooltipString','Labels');
                    labelcolorbutton=uipushtool(ht,'CData',ea_get_icn('colors'),'Tag','Label Color','TooltipString','Label Color');
                end
                % make fv compatible for stats

                caxis([1 64]);

                % prepare colorbutton icon
                try
                    atlasc=squeeze(jetlist(ceil(atlases.colors(atlas)),:));  % color for toggle button icon
                catch
                    ea_error('Atlas color not found.');
                end

                if ~(atlases.types(atlas)>5)
                    colorbuttons(atlascnt)=uitoggletool(ht,'CData',ea_get_icn('atlas',atlasc),'TooltipString',atlases.names{atlas},'ClickedCallback',{@atlasvisible,resultfig,atlascnt},'State',visible);
                end

                % gather contact statistics
                if options.writeoutstats
                    try
                        if isfield(atlases.XYZ{atlas,side},'val') % volumetric atlas
                            thresh=ea_detthresh(atlases,atlas,atlases.XYZ{atlas,side}.val);
                            atsearch=KDTreeSearcher(XYZ.mm(XYZ.val>thresh,:));
                        else % fibertract
                            atsearch=KDTreeSearcher(XYZ.mm(:,1:3));
                        end

                        for el=1:length(elstruct)
                            [~,D]=knnsearch(atsearch,ea_stats.electrodes(el).coords_mm{side});
                            %s_ix=sideix(side,size(elstruct(el).coords_mm{side},1));

                            ea_stats.conmat{el,side}(:,atlas)=D;
                            Dh=D;

                            try
                                in=inhull(ea_stats.electrodes(el).coords_mm{side},fv.vertices,fv.faces,1.e-13*mean(abs(fv.vertices(:))));
                                Dh(in)=0;
                            end
                            ea_stats.conmat_inside_hull{el,side}(:,atlas)=Dh;

                            D(D<mean(pixdim))=0; % using mean here but assuming isotropic atlases in general..
                            ea_stats.conmat_inside_vox{el,side}(:,atlas)=D;
                        end
                    catch
                        warning('Statistics for tract atlas parts are not implemented yet.');
                    end
                end

                %normals{atlas,side}=get(atlassurfs(atlascnt),'VertexNormals');
                if ~(atlases.types(atlas)>5)
                    ea_spec_atlas(atlassurfs(atlascnt,1),atlases.names{atlas},atlases.colormap,setinterpol);
                else
                    pobj.plotFigureH=resultfig;
                    pobj.color=atlasc;
                    pobj.threshold=0.55;
                    pobj.openedit=1;
                    pobj.htH=ht;
                    obj=ea_roi([ea_space([],'atlases'),options.atlasset,filesep,getsidec(side),filesep,atlases.names{atlas}],pobj);
                    atlassurfs(atlascnt,1)=obj.patchH;
                    colorbuttons(atlascnt)=obj.toggleH;
                end

                % set Tags
                try
                    set(colorbuttons(atlascnt),'tag',[thislabel,'_',sidestr{side}])
                    set(atlassurfs(atlascnt,1),'tag',[thislabel,'_',sidestr{side}])
                    set(atlassurfs(atlascnt,1),'UserData',atlaslabels(atlas,side))
                catch
                    keyboard
                end
                atlascnt=atlascnt+1;

                set(gcf,'Renderer','OpenGL')
                axis off
                % set(gcf,'color','w');
                axis equal

                if rand(1)>0.8 % we don't want to show every buildup step due to speed but want to show some buildup.
                    drawnow
                end
            elseif strcmp(atlases.pixdim{atlas,side}, 'discfibers')
                tractPath = [ea_space([],'atlases'),options.atlasset,filesep,getsidec(side,sidestr)];
                tractName = ea_stripext(atlases.names{atlas});

                disctract = load([tractPath, filesep, atlases.names{atlas}]);
                fibcell = disctract.fibcell;
                vals = disctract.vals;
                fibcolor = disctract.fibcolor;

                % Compatibility for fibers combining both sides
                if size(fibcell,2) == 1
                    fibcell = {fibcell};
                end

                if ~iscell(vals)
                    vals = {vals};
                end

                valsAll = vertcat(vals{:});
                alphas = cell(size(vals));

                % Contruct colormap
                colormap(gray);
                gradientLevel = 1024;
                if ~exist('fibcolor', 'var') % Defualt blue, white, red
                    fibcmap = ea_colorgradient(gradientLevel,[0,0,1],[1,1,1],[1,0,0]);
                elseif size(fibcolor,1) == 1 % Blue, white, specified
                    fibcmap = ea_colorgradient(gradientLevel,[0,0,1],[1,1,1],fibcolor);
                elseif size(fibcolor,1) == 2 % Lowest value, white, highest value
                    fibcmap = ea_colorgradient(gradientLevel,fibcolor(1,:),[1,1,1],fibcolor(2,:));
                elseif size(fibcolor,1) == 3 % Lowest value, middle value, highest value
                    fibcmap = ea_colorgradient(gradientLevel,fibcolor(1,:),fibcolor(2,:),fibcolor(3,:));
                end

                % Set alphas of fibers with light color to 0
                colorbarThreshold = 0.60; % Percentage of the pos/neg color to be kept
                negUpperBound = ceil(size(fibcmap,1)/2*colorbarThreshold);
                poslowerBound = floor((size(fibcmap,1)-size(fibcmap,1)/2*colorbarThreshold));

                if isfield(disctract.info, 'PosAmount') && isfield(disctract.info, 'NegAmount')
                    disp(['Fiber colors: Positive (T = ',num2str(min(valsAll(valsAll>0))),' ~ ',num2str(max(valsAll(valsAll>0))), ...
                      '); Negative (T = ',num2str(max(valsAll(valsAll<0))),' ~ ',num2str(min(valsAll(valsAll<0))),').']);
                elseif isfield(disctract.info, 'PosAmount')
                	disp(['Fiber colors: Positive (T = ',num2str(min(valsAll)),' ~ ',num2str(min(valsAll(valsAll>0))), ')']);
                elseif isfield(disctract.info, 'NegAmount')
                	disp(['Fiber colors: Negative (T = ',num2str(max(valsAll)),' ~ ',num2str(min(valsAll)), ')']);
                end

                for fibside=1:2
                    if isempty(fibcell{fibside}) || isempty(vals{fibside})
                        continue;
                    end

                    % Rescale positive/negative tvals to [0 1]/[-1 0]
                    valsRescale = vals{fibside};
                    valsRescale(isnan(valsRescale))=0;
                    valsRescale(valsRescale>0) = ea_rescale(valsRescale(valsRescale>0), [0 1]);
                    valsRescale(valsRescale<0) = ea_rescale(valsRescale(valsRescale<0), [-1 0]);

                    fibcolorInd = valsRescale*(size(fibcmap,1)/2-0.5);
                    fibcolorInd = fibcolorInd+(size(fibcmap,1)/2+0.5);

                    alphas{fibside} = zeros(size(fibcolorInd,1),1);

                    if isfield(disctract.info, 'PosAmount') && isfield(disctract.info, 'NegAmount')
                        alphas{fibside}(round(fibcolorInd)>=poslowerBound) = 1;
                        alphas{fibside}(round(fibcolorInd)<=negUpperBound) = 1;
                    elseif isfield(disctract.info, 'PosAmount')
                        alphas{fibside}(round(fibcolorInd)>=poslowerBound) = 1;
                    elseif isfield(disctract.info, 'NegAmount')
                        alphas{fibside}(round(fibcolorInd)<=negUpperBound) = 1;
                    end

                    alphas{fibside}(round(fibcolorInd)>=poslowerBound) = 1;
                    fibalpha = mat2cell(alphas{fibside},ones(size(fibcolorInd)));

                    % Plot fibers
                    h = streamtube(fibcell{fibside},0.2);
                    nones = repmat({'none'},size(fibcolorInd));
                    [h.EdgeColor] = nones{:};

                    % Calulate fiber colors
                    colors = fibcmap(round(fibcolorInd),:);
                    fibcolor = mat2cell(colors,ones(size(fibcolorInd)));

                    % Set fiber colors and alphas
                    [h.FaceColor] = fibcolor{:};
                    [h.FaceAlpha] = fibalpha{:};

                    if size(vals,2)==2 && fibside == 1
                        sideStr = ', Right side';
                    elseif size(vals,2)==2 && fibside == 2
                        sideStr = ', Left side';
                    else
                        sideStr = '';
                    end

                    uitoggletool(ht, 'CData', ea_get_icn('discfiber'),...
                        'TooltipString', ['Discriminative fibertract: ', tractName, sideStr],...
                        'Tag', ['Discriminative fibertract: ', tractName, sideStr],...
                        'OnCallback', {@showfiber, h},'OffCallback', {@hidefiber, h}, 'State', 'on');

                    set(0,'CurrentFigure',resultfig)
                end

                % Set colorbar tick positions and labels
                cbvals = valsAll(logical(vertcat(alphas{:})));
                % cbvals = valsRescale(logical(alphas));
                if isfield(disctract.info, 'PosAmount') && isfield(disctract.info, 'NegAmount')
                    cbmap = fibcmap;
                    tick = [1, negUpperBound, poslowerBound, length(fibcmap)];
                    poscbvals = sort(cbvals(cbvals>0));
                    negcbvals = sort(cbvals(cbvals<0));
                    ticklabel = [min(cbvals), negcbvals(end), poscbvals(1), max(cbvals)];
                    ticklabel = arrayfun(@(x) num2str(x,'%.2f'), ticklabel, 'Uni', 0);
                elseif isfield(disctract.info, 'PosAmount')
                    cbmap = fibcmap(ceil(length(fibcmap)/2+0.5):end,:);
                    tick = [poslowerBound, length(fibcmap)] - floor(length(fibcmap)/2) ;
                    poscbvals = sort(cbvals(cbvals>0));
                    ticklabel = [poscbvals(1), poscbvals(end)];
                    ticklabel = arrayfun(@(x) num2str(x,'%.2f'), ticklabel, 'Uni', 0);
                elseif isfield(disctract.info, 'NegAmount')
                    cbmap = fibcmap(1:floor(length(fibcmap)/2-0.5),:);
                    tick = [1, negUpperBound];
                    negcbvals = sort(cbvals(cbvals<0));
                    ticklabel = [negcbvals(1), negcbvals(end)];
                    ticklabel = arrayfun(@(x) num2str(x,'%.2f'), ticklabel, 'Uni', 0);
                end

                % Plot colorbar
                cbfig = figure('Visible', 'off');
                ea_plot_colorbar(cbmap, [], 'h', '', tick, ticklabel, axes(cbfig));
                saveas(cbfig, [tractPath, filesep, tractName, '_colorbar.svg']);
                % export_fig(cbfig, [tractPath, filesep, tractName, '_colorbar.png']);
                fprintf('Colorbar exported as:\n%s\n\n', [tractPath, filesep, tractName, '_colorbar.svg']);
            end
        end
    end

    % configure label button to work properly and hide labels as default.
    if ~atlases.discfibersonly % Doesn't exist for pure discfibers atlas
        atlabelsvisible([],[],atlaslabels(:),'off');
        if ~isfield(atlases,'presets')
            set(labelbutton,'OnCallback',{@atlabelsvisible,atlaslabels(:),'on'},'OffCallback',{@atlabelsvisible,atlaslabels(:),'off'},'State','off');
        else
            presetShow = atlases.presets(atlases.defaultset).show;
            set(labelbutton,'OnCallback',{@atlabelsvisible,atlaslabels(presetShow),'on'},'OffCallback',{@atlabelsvisible,atlaslabels(presetShow),'off'},'State','off');
        end
        set(labelcolorbutton,'ClickedCallback',{@setlabelcolor,atlaslabels});

        setappdata(resultfig,'atlassurfs',atlassurfs);
        setappdata(resultfig,'colorbuttons',colorbuttons);
        setappdata(resultfig,'atlht',ht);
        setappdata(resultfig,'labelbutton',labelbutton);
        setappdata(resultfig,'atlaslabels',atlaslabels);
    end

    % save table information that has been generated from nii files (on first run with this atlas set).
    % try
    %     atlases.fv=ifv;
    %     atlases.cdat=icdat;
    %     atlases.XYZ=iXYZ;
    %     atlases.pixdim=ipixdim;
    %     atlases.colorc=icolorc;
    %     atlases.normals=normals;
    % end

    try
        setappdata(resultfig,'atlases',atlases);
        % setappdata(resultfig,'iXYZ',atlases.XYZ);
        % setappdata(resultfig,'ipixdim',atlases.pixdim);
    end

    try
        atlases.rebuild=0; % always reset rebuild flag.
        save([adir,options.atlasset,filesep,'atlas_index.mat'],'atlases','-v7.3');
    end

    if options.writeoutstats
        if exist('prioratlasnames','var')
            if ~isequal(ea_stats.atlases.names,prioratlasnames)
                warning('off', 'backtrace');
                warning('%s: other atlasset used as before. Deleting VAT and Fiberinfo. Saving backup copy.', options.patientname);
                warning('on', 'backtrace');
                ds=load([options.root,options.patientname,filesep,'ea_stats']);
                save(fullfile([options.root,options.patientname],'ea_stats'),'ea_stats','-v7.3');
                save(fullfile([options.root,options.patientname],'ea_stats_backup'),'-struct','ds','-v7.3');
            else
                save(fullfile([options.root,options.patientname],'ea_stats'),'ea_stats','-v7.3');
            end
        else
            save(fullfile([options.root,options.patientname],'ea_stats'),'ea_stats','-v7.3');
        end
    end
end


% open up atlas control viewer
function setlabelcolor(hobj,ev,robject)

co = ea_uisetcolor;
set(robject,'Color',co);


function atlasvisible(hobj,ev,resultfig,atlscnt,onoff)
if ~exist('onoff','var')
    onoff=hobj.State;
end

atls=getappdata(resultfig,'atlassurfs');

if(getappdata(resultfig,'altpressed'))
    cbutn=getappdata(resultfig,'colorbuttons');
    set(cbutn,'State',onoff);
    for el=1:length(atls)
        for side=1:2
            for atlshorz=1:size(atls,2)
                try
                    set(atls(atlscnt,atlshorz), 'Visible', onoff);
                end
            end
        end
    end
else
    for atlshorz=1:size(atls,2)
        try
            set(atls(atlscnt,atlshorz), 'Visible', onoff);
        end
    end
end

% check if new atlas select window is open:
figHandles = findobj('Type','figure');
atlspres=0;
for f=1:length(figHandles)
    if strcmp(figHandles(f).Tag,'atlasselect')
        atlspres=1;
        break
    end
end
if atlspres
    atfig=figHandles(f);
    clear figHandles
    handles=getappdata(atfig,'handles');
    ea_synctree(handles)
end


function atlabelsvisible(hobj,ev,obj,onoff)
labelInd = arrayfun(@(x) isa(x, 'matlab.graphics.primitive.Text'), obj);
if isempty(hobj)
    arrayfun(@(label) set(label,'Visible',onoff), obj(labelInd));
else
    toggleTag = arrayfun(@(t) t.Tag, hobj.Parent.Children(1:end-3), 'Uni', 0);
    toggleState = arrayfun(@(t) t.State, hobj.Parent.Children(1:end-3), 'Uni', 0);

    if strcmp(onoff, 'on')
        arrayfun(@(label) set(label,'Visible',toggleState{strcmp(label.Tag, toggleTag)}), obj(labelInd));
    else
        arrayfun(@(label) set(label,'Visible',onoff), obj(labelInd));
    end
end


function [sides,sidestr]=detsides(type)

switch type
    case 1 % right hemispheric atlas
        sides=1;
        sidestr={'right'};
    case 2 % left hemispheric atlas
        sides=2;
        sidestr={[''],'left'};
    case 3
        sides=1:2;
        sidestr={'right','left'};
    case 4
        sides=1:2;
        sidestr={'right','left'};
    case 5
        sides=1; % midline
        sidestr={'midline'};
    case 6 % probabilistic
        sides=1:2;
        sidestr={'right','left'};
end


function showfiber(~ ,~, discfibers)
arrayfun(@(f) set(f, 'Visible', 'on'), discfibers);


function hidefiber(~ ,~, discfibers)
arrayfun(@(f) set(f, 'Visible', 'off'), discfibers)


function sidec=getsidec(side, sidestr)
switch side
    case 1
        if ~exist('sidestr', 'var')
            sidec='rh';
        elseif strcmp(sidestr{side}, 'midline')
            sidec='midline';
        end
    case 2
        sidec='lh';
end


function in = inhull(testpts,xyz,tess,tol)

% Copyright (c) 2009, John D'Errico
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
%
%     * Redistributions of source code must retain the above copyright
%       notice, this list of conditions and the following disclaimer.
%     * Redistributions in binary form must reproduce the above copyright
%       notice, this list of conditions and the following disclaimer in
%       the documentation and/or other materials provided with the distribution
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.

% inhull: tests if a set of points are inside a convex hull
% usage: in = inhull(testpts,xyz)
% usage: in = inhull(testpts,xyz,tess)
% usage: in = inhull(testpts,xyz,tess,tol)
%
% arguments: (input)
%  testpts - nxp array to test, n data points, in p dimensions
%       If you have many points to test, it is most efficient to
%       call this function once with the entire set.
%
%  xyz - mxp array of vertices of the convex hull, as used by
%       convhulln.
%
%  tess - tessellation (or triangulation) generated by convhulln
%       If tess is left empty or not supplied, then it will be
%       generated.
%
%  tol - (OPTIONAL) tolerance on the tests for inclusion in the
%       convex hull. You can think of tol as the distance a point
%       may possibly lie outside the hull, and still be perceived
%       as on the surface of the hull. Because of numerical slop
%       nothing can ever be done exactly here. I might guess a
%       semi-intelligent value of tol to be
%
%         tol = 1.e-13*mean(abs(xyz(:)))
%
%       In higher dimensions, the numerical issues of floating
%       point arithmetic will probably suggest a larger value
%       of tol.
%
%       DEFAULT: tol = 0
%
% arguments: (output)
%  in  - nx1 logical vector
%        in(i) == 1 --> the i'th point was inside the convex hull.
%
% Example usage: The first point should be inside, the second out
%
%  xy = randn(20,2);
%  tess = convhulln(xy);
%  testpoints = [ 0 0; 10 10];
%  in = inhull(testpoints,xy,tess)
%
% in =
%      1
%      0
%
% A non-zero count of the number of degenerate simplexes in the hull
% will generate a warning (in 4 or more dimensions.) This warning
% may be disabled off with the command:
%
%   warning('off','inhull:degeneracy')
%
% See also: convhull, convhulln, delaunay, delaunayn, tsearch, tsearchn
%
% Author: John D'Errico
% e-mail: woodchips@rochester.rr.com
% Release: 3.0
% Release date: 10/26/06

% get array sizes
% m points, p dimensions
p = size(xyz,2);
[n,c] = size(testpts);
if p ~= c
    error 'testpts and xyz must have the same number of columns'
end
if p < 2
    error 'Points must lie in at least a 2-d space.'
end

% was the convex hull supplied?
if (nargin<3) || isempty(tess)
    tess = convhulln(xyz);
end
[nt,c] = size(tess);
if c ~= p
    error 'tess array is incompatible with a dimension p space'
end

% was tol supplied?
if (nargin<4) || isempty(tol)
    tol = 0;
end

% build normal vectors
switch p
    case 2
        % really simple for 2-d
        nrmls = (xyz(tess(:,1),:) - xyz(tess(:,2),:)) * [0 1;-1 0];

        % Any degenerate edges?
        del = sqrt(sum(nrmls.^2,2));
        degenflag = (del<(max(del)*10*eps));
        if sum(degenflag)>0
            warning('inhull:degeneracy',[num2str(sum(degenflag)), ...
                ' degenerate edges identified in the convex hull'])

            % we need to delete those degenerate normal vectors
            nrmls(degenflag,:) = [];
            nt = size(nrmls,1);
        end
    case 3
        % use vectorized cross product for 3-d
        ab = xyz(tess(:,1),:) - xyz(tess(:,2),:);
        ac = xyz(tess(:,1),:) - xyz(tess(:,3),:);
        nrmls = cross(ab,ac,2);
        degenflag = false(nt,1);
    otherwise
        % slightly more work in higher dimensions,
        nrmls = zeros(nt,p);
        degenflag = false(nt,1);
        for i = 1:nt
            % just in case of a degeneracy
            % Note that bsxfun COULD be used in this line, but I have chosen to
            % not do so to maintain compatibility. This code is still used by
            % users of older releases.
            %  nullsp = null(bsxfun(@minus,xyz(tess(i,2:end),:),xyz(tess(i,1),:)))';
            nullsp = null(xyz(tess(i,2:end),:) - repmat(xyz(tess(i,1),:),p-1,1))';
            if size(nullsp,1)>1
                degenflag(i) = true;
                nrmls(i,:) = NaN;
            else
                nrmls(i,:) = nullsp;
            end
        end
        if sum(degenflag)>0
            warning('inhull:degeneracy',[num2str(sum(degenflag)), ...
                ' degenerate simplexes identified in the convex hull'])

            % we need to delete those degenerate normal vectors
            nrmls(degenflag,:) = [];
            nt = size(nrmls,1);
        end
end

% scale normal vectors to unit length
nrmllen = sqrt(sum(nrmls.^2,2));
% again, bsxfun COULD be employed here...
%  nrmls = bsxfun(@times,nrmls,1./nrmllen);
nrmls = nrmls.*repmat(1./nrmllen,1,p);

% center point in the hull
center = mean(xyz,1);

% any point in the plane of each simplex in the convex hull
a = xyz(tess(~degenflag,1),:);

% ensure the normals are pointing inwards
% this line too could employ bsxfun...
%  dp = sum(bsxfun(@minus,center,a).*nrmls,2);
dp = sum((repmat(center,nt,1) - a).*nrmls,2);
k = dp<0;
nrmls(k,:) = -nrmls(k,:);

% We want to test if:  dot((x - a),N) >= 0
% If so for all faces of the hull, then x is inside
% the hull. Change this to dot(x,N) >= dot(a,N)
aN = sum(nrmls.*a,2);

% test, be careful in case there are many points
in = false(n,1);

% if n is too large, we need to worry about the
% dot product grabbing huge chunks of memory.
memblock = 1e6;
blocks = max(1,floor(n/(memblock/nt)));
aNr = repmat(aN,1,length(1:blocks:n));
for i = 1:blocks
    j = i:blocks:n;
    if size(aNr,2) ~= length(j)
        aNr = repmat(aN,1,length(j));
    end
    in(j) = all((nrmls*testpts(j,:)' - aNr) >= -tol,1)';
end
