%% 读取图像
rawCFA = rawread('test_img.raw');      % 原始CFA数据（单通道）
rgbImage = raw2rgb('test_img.raw');    % 彩色RGB图像（仅用于显示）

%% 中值滤波（处理原始CFA数据）
windowSize = 3;
filteredCFA = medfilt2(rawCFA, [windowSize windowSize]);

%% 显示对比结果
figure;
subplot(1, 3, 1);
imshow(rgbImage);
title('原彩色图像');

subplot(1, 3, 2);
imshow(rawCFA, []);
title('原始CFA数据');

subplot(1, 3, 3);
imshow(filteredCFA, []);
title('中值滤波后CFA');

%% 保存为TXT文件（十六进制格式）
% 获取尺寸
[img_height, img_width] = size(filteredCFA);

% 打开文件
fileID = fopen('median_filtered_raw.txt', 'w');

% 写入数据
for i = 1:img_height
    for j = 1:img_width
        % 获取像素值
        pixelValue = filteredCFA(i, j);
        
        % 根据数据类型决定输出格式
        if isa(pixelValue, 'uint16')
            % 16位数据：输出4位十六进制
            fprintf(fileID, '%04x', pixelValue);
        elseif isa(pixelValue, 'uint8')
            % 8位数据：输出2位十六进制
            fprintf(fileID, '%02x', pixelValue);
        else
            % double类型：先转为uint16再输出
            fprintf(fileID, '%04x', uint16(pixelValue));
        end
        
        % 每列之间加空格（可选，便于阅读）
        if j < img_width
            fprintf(fileID, ' ');
        end
    end
    % 每行结束后换行
    fprintf(fileID, '\n');
end

% 关闭文件
fclose(fileID);

fprintf('TXT文件已保存：median_filtered_raw.txt\n');
fprintf('图像尺寸：%d × %d\n', img_height, img_width);