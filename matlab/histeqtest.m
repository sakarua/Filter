close all; clear; clc;

%% 读取图像
originalImage=imread('test_img.bmp');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 直方图均衡
processedImage=histeq(grayImage);
%% 输出比较
% 显示原图和处理后的图像
subplot(1, 2, 1);
imshow(grayImage);
title('灰度化图像');

subplot(1, 2, 2);
imshow(processedImage);
title('直方图均衡化图像');