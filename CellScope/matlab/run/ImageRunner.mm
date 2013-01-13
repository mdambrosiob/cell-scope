//
//  ImageRunner.m
//  CellScope
//
//  Runs the algorithm on an image, or multiple images selected by the user
//
//  Created by Wayne Gerard on 12/8/12.
//  Copyright (c) 2012 Matthew Bakalar. All rights reserved.
//
//

#import "ImageRunner.h"
#import "ImageTools.h"
#import "Globals.h"
#import "MatrixOperations.h"
#import <opencv2/core/core_c.h>

@implementation ImageRunner

@synthesize patchSize = _patchSize, orig = _orig, hogFeatures = _hogFeatures;

/**
    Converts an image (as a Mat) to a red-channel only normalized image, with pixel intensities between 0..1
    @param image The image, assumed to be a color image with all 3 channels
    @return Returns an the red-channel normalized image
 */
- (Mat) getRedImageNormalizedImage: (Mat) image {
    // ASK: Is this right?
    // Use only red channel for image
    
    // WN: I have no idea if this is the right thing to be doing
    // This seems to suggest so: http://www.cs.bc.edu/~hjiang/c335/notes/lec3/lec3.pdf
    Mat red(image.rows, image.cols, CV_8UC1);
    Mat green(image.rows, image.cols, CV_8UC1);
    Mat blue(image.rows, image.cols, CV_8UC1);
    cvSplit(&image, &red, &green, &blue, 0);
    
    // ASK: Normalize to values between [0, 1] ?
    // Normalize the image to values between 0..1
    Mat orig = Mat(image.rows, image.cols, CV_32F);
    Mat red_32F(image.rows, image.cols, CV_32F);
    convertScaleAbs(red, red_32F);
    cvNormalize(&orig, &red_32F);
    normalize(red_32F, orig, 0, NORM_MINMAX);
    return orig;
}

/**
    Checks patches for completness, and if patches are complete then returns a dictionary containing the following
    information:
    
    1) The column [col: NSNumber]
    2) The row [row: NSNumber]
    3) The patch [patch: Mat]
    4) The binary patch
    5) Possibly the gradient patch, if HoG features are enabled [gradPatch: Mat]
 
    @param row The row for this centroid
    @param col The column for this centroid
    @return    Returns a NSMutableDictionary containing the above 4 values with the key-value pairs in parantheses.
               Will return NULL if this is a partial patch
 */
- (NSMutableDictionary*) storeGoodCentroidsWithRow:(int) row withCol:(int) col {
    
    NSMutableDictionary* stats = [NSMutableDictionary dictionary];
    
    /////////////////////////////////
    // Patch Completeness Checking //
    /////////////////////////////////
    bool partial = NO;
    
    // Lower bounds checking
    int lowerC = col - self.patchSize / 2;
    int lowerR = row - self.patchSize / 2;
    if (lowerC <= 0 || lowerR <= 0) {
        partial = YES;
    }
    
    // Higher bounds checking
    int higherC = (col + (self.patchSize / 2 - 1));
    int higherR = (row + (self.patchSize / 2 - 1));
    
    if ((higherC > self.orig.cols) || (higherR  > self.orig.rows)) {
        partial = YES;
    }

    if (partial) {
        return NULL;
    }

    //////////////////////////
    // Store good centroids //
    //////////////////////////
    
    [stats setValue:[NSNumber numberWithInt:col] forKey:@"col"];
    [stats setValue:[NSNumber numberWithInt:row] forKey:@"row"];
    
    // Indices in matlab are 1 based
    int row_start = (row - self.patchSize / 2) - 1;
    int row_end = row + (self.patchSize / 2 - 1) - 1;
    int col_start = col - self.patchSize / 2 - 1;
    int col_end = col + (self.patchSize / 2 - 1) - 1;
    Range rows = Range(row_start, row_end);
    Range cols = Range(col_start, col_end);
    
    Mat _patch = self.orig.operator()(rows, cols);
    id patch = [MatrixOperations convertMatToObject:_patch];
    [stats setValue:patch forKey: @"patch"];

    /* WAYNE NOTE: This isn't being used anywhere - do we need this method?
    if (self.hogFeatures) {
        int patchCenter = self.patchSize / 2;
        int row_start = row - patchCenter - 1;
        int row_end = row + patchCenter - 1;
        int col_start = col - patchCenter - 1;
        int col_end = col + patchCenter - 1;
        
        Range rows = Range(row_start, row_end);
        Range cols = Range(col_start, col_end);
        Mat _gradpatch = gradim(rows, cols);
        id gradpatch = [MatrixOperations convertMatToObject:_gradpatch];
        [stats setValue:gradpatch forKey: @"gradpatch"];
    }
     */
    
    return stats;
}

/**
    @param img The Image to run on
    @return Returns a CSV file with centroids and scores
 */
- (void) runWithImage: (UIImage*) img
{
    
    // TODO: Return CSV instead of void
    /*% OUTPUT: CSV file(s) with centroids and scores
    % - ctrs_sort: array of centroids, sorted by descending patch score. Each
    %   row contains (row,col) indices.
    % - scrs_sort: corresponding scores (likelihood of being bacilli)
    */


    // Convert the image to an OpenCV matrix
    Mat image = [ImageTools cvMatWithImage:img];
    if(!image.data) // IM
    {
        CSLog(@"Could not load image with filename"); 
        return;
    }
    
    self.orig = [self getRedImageNormalizedImage:image];
    NSMutableArray* data = [NSMutableArray array];
    
    // Perform object identification
    imbw = blobid(orig,0); % Use Gaussian kernel method
    
    imbwCC = bwconncomp(imbw);
    imbwCC.stats = regionprops(imbwCC,orig,'WeightedCentroid');

    // Computer gradient image for HoG features
    if (self.hogFeatures) { //
        // WAYNE NOTE: Pretty sure this isn't being used anywhere. Confirm?
       // gradim = compute_gradient(orig,8);
    }
    
    int patchCount = 0;
    
    // update vector of centroid values
    centroids = round(vertcat(imbwCC.stats(:).WeightedCentroid)); // col idx in col 1, row idx in col 2

    int numObjects = imbwCC.numObjects;
    
    for (int j = 0; j < numObjects; j++) { // IM
        int col = centroids[j][0];
        int row = centroids[j][2];
        
        NSMutableDictionary* stats  = [self storeGoodCentroidsWithRow:row withCol:col];
        if (stats != NULL) { // If not a partial patch
            patchCount++;
            [data addObject:stats];
            
        }
    }
    
    // Calculate features
    data = calcfeats(data, patchSize, hogFeatures);
    Mat train_max;
    Mat train_min;
    

    ////////////////////////////////////
    // Store Centroids, Features  //
    ////////////////////////////////////
    
    NSMutableArray* centroids  = [NSMutableArray array];
    
    Mat features;
    if (self.hogFeatures) {
        features = Mat(patchCount, 3, CV_8UC1);
    } else {
        features = Mat(patchCount, 2, CV_8UC1);
    }
    NSMutableArray* features   = [NSMutableArray array];
    
    for (int j = 0; j < patchCount; j++) {
        NSMutableDictionary* stats = [data objectAtIndex:j];
        
        // Centroid
        NSArray* centroid =  [NSArray arrayWithObjects:
                              [stats valueForKey:@"row"],
                              [stats valueForKey:@"col"],
                              nil];
        
        [centroids addObject: centroid];
        
        // Feature
        features.at<float>(j, 0) = [[stats valueForKey:@"phi"] floatValue];
        features.at<float>(j, 1) = [[stats valueForKey:@"geom"] floatValue];
        
        if (self.hogFeatures) {
            features.at<float>(j, 2) = [[stats valueForKey:@"hog"] floatValue];
        }
    }
    
    //////////////////////
    // Prepare Features //
    //////////////////////
    
    // Prepare features and run object-level classifier
    Mat xTest;
    Mat yTest = Mat::zeros(self.patchSize, 1, CV_8UC1);
    //Xtest = features
    
    // Minmax normalization of features
    //ytest is a patchSize x 1 matrix, so repmat(train_max, size(ytest_dummy)) = repmat(train_max, patchSize, 1)
    Mat maxMatrix = [MatrixOperations repMat:train_max withRows:self.patchSize withCols:1];
    Mat minMatrix = [MatrixOperations repMat:train_min withRows:self.patchSize withCols:1];

    Mat FeaturesMinusMin;
    Mat MaxMinusMin;
    subtract(maxMatrix, minMatrix, MaxMinusMin);
    subtract(features, minMatrix, FeaturesMinusMin);
    
    Xtest = (Xtest-minmat)./(maxmat-minmat); // ./ means treat it as an array
    
    //////////////////////
    // Classify Objects //
    //////////////////////
    
    // LibSVM IKSVM classifier
    [pltest, accutest, dvtest] = svmpredict(double(ytest_dummy),double(Xtest),model,'-b 1');
    NSMutableArray* dvtest = [NSMutableArray array];
    dvtest = dvtest(:,model.Label==1);
    NSMutableArray* scoreDictionaryArray = [NSMutableArray array];
    
    // NOTE: We don't need to do logistic regression because it's built into LibSVM

    ////////////////////////////////////
    // Sort Scores and Centroids (IM) //
    ////////////////////////////////////
    
    [sortedDictionaryArray sortUsingComparator:^(NSMutableDictionary* dictOne, NSMutableDictionary* dictTwo){
        score1 = [dictOne valueForKey:@"value"];
        score2 = [dictTwo valueForKey:@"value"];
        if (score1 < score2)
            return NSOrderedAscending;
        else
            return NSOrderedDescending;
    }];
    
    // Now sortedDictionaryArray is sorted in descending order
    // Sort sortedScores and centroids using the indices attached to the sortedDictionaryArray

    NSMutableArray* sortedScores = [NSMutableArray array];
    
    for (int i = 0; i < [sortedScores count]; i++) {
        NSMutableDictionary* score = [sortedScores objectAtIndex:i];
        NSNumber* value = [score valueForKey:@"value"];
        int index = [[score valueForKey:@"index"] intValue];
        
        NSNumber* oldObject = [centroids objectAtIndex:i];
        NSNumber* sortedObject = [centroids objectAtIndex:index];
        
        [centroids replaceObjectAtIndex:index withObject:oldObject];
        [centroids replaceObjectAtIndex:i withObject:sortedObject];
        [sortedScores addObject:value];

    }
    
    //////////////////////////////////////
    // Drop Low-confidence Patches (IM) //
    //////////////////////////////////////

    float lowlim = 1e-6;
    NSMutableIndexSet* lowConfidencePatches = [NSMutableIndexSet indexSet];

    for (int i = 0; i < [sortedScores count]; i++) {
        float score = [sortedScores objectAtIndex:i];
        if (i <= lowlim) {
            [lowConfidencePatches addIndex:i];
        }
    }
    [sortedScores removeObjectsAtIndexes:lowConfidencePatches];
    [centroids removeObjectsAtIndexes:lowConfidencePatches];
    
    
    //////////////////////////////////////////////
    // Non-max Suppression Based on Scores (IM) //
    //////////////////////////////////////////////
    
    float maxDistance = ((self.orig.rows ** 2) + (self.orig.cols ** 2)) ** 0.5;
    
    // Setup rows and columns for next step
    NSMutableArray* centroidRows = [NSMutableArray array];
    NSMutableArray* centroidCols = [NSMutableArray array];
    for (int i = 0; i < [centroids count]; i++) {
        NSArray* centroid = [centroids objectAtIndex:i];
        int row = [centroid objectAtIndex:0];
        int col = [centroid objectAtIndex:1];
        [centroidRows addObject:[NSNumber numberWithInt:row]];
        [centroidCols addObject:[NSNumber numberWithInt:col]];
    }
    
    NSMutableIndexSet* suppressedPatches = [NSMutableIndexSet indexSet];
    for (int i = 0; i < [sortedScores count]; i++) { // This should start from the highest-scoring patch
        NSArray* centroid = [centroids objectAtIndex:i];
        int row = [centroid objectAtIndex:0];
        int col = [centroid objectAtIndex:1];
        
        NSArray* rowCopy = [NSArray arrayWithArray:centroidRows];
        NSArray* colCopy = [NSArray arrayWithArray:centroidCols];
        NSMutableArray* distance = [NSMutableArray array];
        
        float minDistance = 1e99;
        int minDistanceIndex = -1;
        
        for (int j = 0; j < [rowCopy count]; j++;) {
            int newRowVal = row - [rowCopy objectAtIndex: j];
            int newColVal = col - [colCopy objectAtIndex: j];

            newRowVal = newRowVal ** 2;
            newColVal = newColVal ** 2;
            
            float newVal = newRowVal + newColVal;
            newVal = newVal ** 0.5;
            
            if (newVal < minDistance && newVal != 0) {
                minDistance = newVal;
                minDistanceIndex = j;
            }
            
            
            [distance addObject:[NSNumber numberWithFloat:newVal]];
        }
        
        // Find the patch with the minimum distance (that isn't the current patch, where distance == 0)
        
        // See if it's too close. If it is, then suppress the patch
        float cutoff = 0.75 * self.patchSize; // non-max suppression parameter, "too close" distance
        if(minDistance <= cutoff) { // if too much overlap
            // WG Note: Why is this necessary again?
            // prevent triggering non-max again/get rid of lower-score object
            NSArray* newCentroid = [NSArray arrayWithObjects:
                                    [NSNumber numberWithInt:(-1 * self.orig.rows)],
                                    [NSNumber numberWithInt:(-1 * self.orig.cols)],
                                    nil]        
            // Suppress this patch
            [suppressedPatches addIndex:i];
        }
    }

    [sortedScores removeObjectsAtIndexes:suppressedPatches];
    [centroids removeObjectsAtIndexes:suppressedPatches];
    
    //////////////////
    // Write to CSV //
    //////////////////
    
    csvwrite(['./out_',fname(1:end-4),'.csv'],[ctrs_sort scrs_sort]);
}

@end
