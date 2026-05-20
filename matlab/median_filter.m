%% 读取图像
originalImage = imread('test_img.bmp');
figure;
%% 显示原图
subplot(1, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
medianImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 3;  % 窗口大小，奇数
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height);%窗口下边界
        c1 = max(j - halfWindowSize, 1);%窗口左边界
        c2 = min(j + halfWindowSize, img_width);%窗口右边界
        
        % 提取窗口
        window = grayImage(r1:r2, c1:c2);
        
        % 计算窗口内的中值
        localmedian = median(window(:));
        
        medianImage(i,j) = localmedian;
    end
end
%% 无符号8bit
medianImage = uint8(medianImage);   
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);

% 显示原图和处理后的图像
subplot(1, 3, 2);
imshow(grayImage);
title('灰度化图像');

subplot(1, 3, 3);
imshow(medianImage);
title('中值滤波图像');

%% 获取图像的尺寸信息
[image_height, image_width, num_channels] = size(medianImage);

%% 打开文件以写入
file_id = fopen('matlab_bmp.txt', 'w+');

%% 遍历每一个像素并写入到文件中
for row_index = 1:image_height
    for col_index = 1:image_width 
        for channel_index = 1:num_channels
            % 将每个像素值写入文件，以十六进制格式表示
            fprintf(file_id, '%02x', medianImage(row_index, col_index, channel_index));
        end
        % 每行像素结束后换行
        fprintf(file_id, '\n');
    end
end

%% 关闭文件
fclose(file_id);
