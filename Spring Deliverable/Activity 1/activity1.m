%% Imports the stereo video
[stereoP,stereoPath] = uigetfile(path,'Select the file for the stereoParams');
stereoParams = strcat(stereoPath,'',stereoP);
stereoParams = load(stereoParams);
stereoParams = stereoParams.stereoParams;

%% Set the outputVideoParams
nFrames = 486;
F(1:nFrames) = struct('cdata',zeros(512,1392,3,'uint8'),'colormap',[]);


%% Train detector
negativeFolder = uigetdir(path,'Select the folder for Negative Images');
positiveInstances = uigetfile(path,'Select the file for the positive Instances');
load positiveInstances;
detectorFile = 'CarDetector.xml';
trainCascadeObjectDetector(detectorFile, positiveInstances, negativeFolder, 'FalseAlarmRate',0.01,'NumCascadeStages',10);
detector = vision.CascadeObjectDetector(detectorFile);

  
%Identifies the vehicle directly in front and draws a bounding box around this vehicle
leftcontentsDir = uigetdir(path,'Select the folder for the left images');
rightcontentsDir = uigetdir(path,'Select the folder for the right images');
h = waitbar(0,'Processing Video 0%');
for k = 1:486
    perc = k/nFrames;
    waitbar(perc,h,sprintf('Processing Video %d%%',int8(perc*100)));

    % Uses the stereo video to estimate the distance to the vehicle in front:
    leftcontent = dir(leftcontentsDir);
    rightcontent = dir(rightcontentsDir);
    leftFilename = leftcontent(k).name;
    rightFilename = rightcontent(k).name;
    leftImgPath = strcat(leftcontentsDir,'\',leftFilename);
    rightImgPath = strcat(rightcontentsDir,'\',rightFilename);
    frameLeft = imread(leftImgPath);
    frameRight = imread(rightImgPath);
    

    %Rectifies each stereo frame to ensure the left and right images are aligned
    [frameLeftRect, frameRightRect] = rectifyStereoImages(frameLeft, frameRight, stereoParams);
    frameLeftGray = rgb2gray(frameLeftRect);
    frameRightGray = rgb2gray(frameRightRect);

    %Detect Cars
    bboxes = step(detector,frameLeftGray);

    % Builds a disparity map between the left and right images
    disparityMap = disparity(frameLeftGray, frameRightGray,'DisparityRange',[0 64]);

    % Reconstructs the disparity map to generate a point cloud
    point3D = reconstructScene(disparityMap,stereoParams);

% Uses that point cloud to find the distance to the center of the vehicle bounding box
    % To reduce noise it may be preferable to use an average of a small group of pixels at the center
    ptCloud = pcdenoise(point3D);
    ptCloud = ptCloud/1000;
    if ~isempty(bboxes)
        centroids = [round(bboxes(:,1) + bboxes(:,3)/2),round(bboxes(:,2) +bboxes(:,4)/2)];
        %Find the 3-D world coordinates
        centroidsIdx = sub2ind(size(disparityMap),centroids(:,2),centroids(:,1));
        X = point3D(:,:,1);
        Y = point3D(:,:,2);
        Z = point3D(:,:,3);
        centroids3D = [X(centroidsIdx),Y(centroidsIdx), Z(centroidsIdx)];

        %Distance from camera in meters
        dists = sqrt(sum(centroids3D .^2,2))/1000;

        %Display the detected cars and distances
        labels = cell(1,numel(dists));
        for i=1:numel(dists)
            labels{i} = sprintf('%.2f meters',dists(i));
        end
        dispFrame = insertObjectAnnotation(frameLeftRect, 'rectangle',bboxes,labels);

    else
        dispFrame = frameLeftRect;
    end
% Outputs the left side source video with the following items overlaid:
    % Bounding box around the vehicle in front
    % Text above or below the bounding box stating:
        % Estimated distance to the center of the vehicle bounding box
        % Location of the vehicle bounding box center (in pixels measured relative to image center)
        % Note: text should include units and a label for each item (e.g. Distance: 20 meters)
    F(k) = im2frame(dispFrame);
end
% Outputs a figure plotting the distance to the vehicle in front throughout the duration of the video.