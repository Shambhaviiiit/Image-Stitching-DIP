function mat = vec2mat_(vec, cols, pad)
    % vec: Input vector (1D array)
    % cols: Number of columns for the output matrix
    % pad: Value used for padding (optional, default is NaN)
    
    if nargin < 3
        pad = NaN; % Default padding value
    end
    
    len = length(vec);             % Length of the input vector
    rows = ceil(len / cols);       % Calculate required rows
    padded_len = rows * cols;      % Total number of elements after padding
    
    % Pad the vector with the specified value
    vec = [vec(:); pad * ones(padded_len - len, 1)];
    
    % Reshape the padded vector into the specified number of columns
    mat = reshape(vec, cols, rows)';
end
