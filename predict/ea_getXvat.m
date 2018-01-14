function [X,XR]=ea_getXvat(M,options)
XR=nan;

selectedregressor=M.clinical.vars{M.ui.clinicallist};
selectedregressor=selectedregressor(M.ui.listselect,:);
if size(selectedregressor,2)==1
    bihemispheric=0;
elseif size(selectedregressor,2)==2
    bihemispheric=1;
else
    ea_error('Please select a regressor with entries for each hemisphere or each patient to perform this action.');
end

cnt=1;

for pt=M.ui.listselect
    nii=ea_load_nii([options.root,options.patientname,filesep,'statvat_results',filesep,'s',num2str(pt),'_lh.nii']);
    if ~exist('X','var')
        X=nan(length(M.ui.listselect),numel(nii.img));
        if bihemispheric
            XR=X;
        end
    end
    X(cnt,:)=nii.img(:);
    if bihemispheric
        nii=ea_load_nii([options.root,options.patientname,filesep,'statvat_results',filesep,'s',num2str(pt),'_rh.nii']);
        XR(cnt,:)=nii.img(:);
        XR(cnt,:)=double(logical(XR(cnt,:)));
    else
        nii=ea_load_nii([options.root,options.patientname,filesep,'statvat_results',filesep,'s',num2str(pt),'_rh_flipped.nii']);
        X(cnt,:)=X(cnt,:)+nii.img(:)';
    end
    X(cnt,:)=double(logical(X(cnt,:)));
    
    cnt=cnt+1;
end