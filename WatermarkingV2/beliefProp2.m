clear;
clc;
close all;

%load('data/population.mat');
%data = FileData;
load('data/frequencies.mat');
load('data/correlationsTrue.mat');
load('data/MAFs.mat');
load('data/cValues.mat');
load('data/shannons.mat');
%clear FileData
%for each family

%Resize Main Data
pheSize = 50;
numIterations = 2; %100
dataSize = 1000;
wlens = 100;
families = 1;
SPs = 1:20;
difPriCoef = 0:0.1:1;
freqs = frequencies(:,1:dataSize)';
colabs = 10;%2:10;
%aInt = 0.1; %Attacker Intelligence
MAFs = MAFs(1:dataSize)';
%frequencies = createFrequencies(MAFs, dataSize);
ps = zeros([4*20 length(wlens)]);
%totalSharingEstimated = length(SPs);
allResults = zeros([length(difPriCoef)*length(colabs) length(wlens)*4]);
err = 0.01;

vars2 = zeros([dataSize 3]);
for i = 1:dataSize
    vars2(i,1) = (1-MAFs(i))*(1-MAFs(i));
    vars2(i,2) = 2*MAFs(i)*(1-MAFs(i));
    vars2(i,3) = MAFs(i)*MAFs(i);
end    

for famIteration = families
    p1_01 = zeros([length(difPriCoef)*length(colabs) length(wlens)*4]);
    file = ['family/fam' num2str(famIteration) '/fam' num2str(famIteration) '.mat'];
    load(file);
    personalData = family(3,1:dataSize)';
    %PART 2 : RECEIVE INFORMATION STAGE
    %*************************************************************************************************
    %Part 2a: Receiving family information (Moved to upper stages of loop since no change occurs during iterations)
    Nodes_fam = createFamNodes(dataSize, family);

    %Part 2b: Receiving phenotype information
    Nodes_phe = createPhenotypes(pheSize,cCheckList,family);
    
    %No need to keep the cell structure since phenotype and family doesnt
    %recieve information from variable node.
    phes = cell2mat(Nodes_phe(:,2));
    fams = cell2mat(Nodes_fam(:,1));
    pheIs = cell2mat(Nodes_phe(:,1));
    %pheIsA = sort(pheIs(randperm(pheSize,round(pheSize*aInt))));
    %famIsA = sort(randperm(dataSize,round(dataSize*aInt)))';
    %*************************************************************************************************

    %PART 3: GENERATION OF FACTOR AND VARIABLE NODES
    %*************************************************************************************************

    %Part 3a: Generate Nodes_fam
    %Created before since no need for recreation for each SP

    %Part 3b: Generate Nodes_phe
    %Created before since no need for recreation for each SP
    
    %PART 6: TESTING AGAINST ATTACKS
    for difs = 1:length(difPriCoef)
        precisionH = zeros([length(colabs) length(wlens)]);
        precisionHR = zeros([length(colabs) length(wlens)]);
        precisionE = zeros([length(colabs) length(wlens)]);
        precisionER = zeros([length(colabs) length(wlens)]);
        utilityScores = zeros([length(SPs) length(wlens)]);
        kullbacks = cell(length(SPs), length(wlens));
        for w = 1:length(wlens)
            %Part 3c: Generate Nodes_c (Correlation Nodes)
            corr = correlations;
            count = 1; 
            while count <= length(corr)
                if corr(count,1) > dataSize || corr(count,2) > dataSize
                    corr(count,:) = [];
                else
                    count = count+1;
                end
            end
            cNum = length(corr);
            Nodes_c = corr;
            Nodes_c = num2cell(Nodes_c);
            Nodes_c(:,6) = {[1/3 1/3 1/3]}; % Marginal Probability Distribution of Correlations from Current Iteration
            Nodes_c(:,7) = {[1/3 1/3 1/3]}; % Marginal Probability Distribution of Correlations from Previous Iteration

            %Part 3c2 - Optional data structures for optimal search
            cCheckList = unique(union(corr(:,1),corr(:,2)));
            cIndexMatrix = createCrrMatrix(corr, cCheckList);
            %save('data/cValues.mat','cCheckList','cIndexMatrix');

            %Part 3d: Generate Nodes_u(self_prob_dist, Nodes_var, frequencies, MAFs, Nodes_c) 
            Nodes_u = cell(dataSize, 5);
            Nodes_u(:,1) = {[1/3 1/3 1/3]};
            Nodes_u(:,2) = {[1/3 1/3 1/3]};
            for i = 1:dataSize
                Nodes_u(i,3) = {freqs(i,:)};
            end
            for i = 1:dataSize
                Nodes_u(i,4) = {MAFs(i,:)};
            end
            for i=1:cNum
                x = cell2mat(Nodes_c(i,1));
                y = cell2mat(Nodes_c(i,2));
                Nodes_u{x,5} = [cell2mat(Nodes_u(x,5)), y];  %gnode ids!
            end

            %Part 3e: Generate Nodes_a (self_prob_dist, Nodes_var, shannonEntropy, MAFs)
            Nodes_a = Nodes_u;
            Nodes_a = Nodes_a(:,1:end-1); %Removing correlation data (in last index) from attack nodes since it is not needed
            for i = 1:dataSize
                Nodes_a{i,3} = [1/3 1/3 1/3];
            end

            %Part 3f: Generate Nodes_var(self_prob_dist, Nodes_u, Nodes_a, Nodes_c, Nodes_fam, Nodes_phe) 
            Nodes_var = cell(dataSize, 6);
            Nodes_var(:,1) = {[]};
            Nodes_var(:,2) = Nodes_u(:,1);
            Nodes_var(:,3) = Nodes_a(:,1);
            Nodes_var(:,4) = {[]};
            for i=1:cNum
                x = cell2mat(Nodes_c(i,1));
                y = cell2mat(Nodes_c(i,2));
                Nodes_var{x,4} = [cell2mat(Nodes_var(x,4)), y];  %gnode ids!
            end
            Nodes_var(:,5) = Nodes_fam(:,1);
            Nodes_var(:,6) = {[]};
            for i=1:size(Nodes_phe,1)
                Nodes_var(cell2mat(Nodes_phe(i,1)),6) = Nodes_phe(i,2);
            end
            %*************************************************************************************************
            sharedDataSoFar = zeros([length(SPs) dataSize]);
            %PART 4: BELIEF PROPAGATION
            %*************************************************************************************************
            for i = 1:numIterations
                
                %Part4a_0: Get cell2mats beforehand for making the iterations faster
                cors = cell2mat(Nodes_c(:,6));

                %Part 4a: Calculating Nodes_var(self_prob_dist, Nodes_u, Nodes_a, Nodes_c, Nodes_fam, Nodes_phe)
                %Last 2 parameter never changes
                for j = 1:dataSize
                    %Starting with genomic frequency and family information
                    prob = fams(j,:);
                    %If j is one of the correlated data points
                    if sum(ismember(cCheckList,j))>0
                        k = 1;
                        while cCheckList(k) ~= j
                            k = k + 1;    
                        end
                        indexes = unique(cIndexMatrix(:,k+1)); 

                        %First element -1 should be discarded therefore start from 2.
                        for k = 2:length(indexes)
                            corr_mssg = cors(indexes(k),:); 
                            prob = prob.*corr_mssg;
                        end
                    end
                    %If j has an available phenotype information
                    if sum(ismember(pheIs,j))>0
                        k = 1;
                        while pheIs(k) ~= j
                            k = k + 1;    
                        end
                        prob = prob.*phes(k,:); 
                    end
                    prob = prob./norm(prob,1);
                    Nodes_var(j,1) = {prob};
                end

                %Part4bcd_0: Get cell2mats beforehand for making the iterations faster
                vars = cell2mat(Nodes_var(:,1));
                corIns = cell2mat(Nodes_c(:,1:2));

                %Part 4d: Calculating Nodes_c
                for j = 1:cNum
                    prob = calculate_c_local(Nodes_c, j);
                    Nodes_c(j,6) = {prob};
                    Nodes_c(j,7) = {vars(corr(j,1),:)};
                end
                %Part 4d: Calculating Family Nodes and Phenotype Nodes
                %Since already observed they come unchanged
            end
            vars = cell2mat(Nodes_var(:,1));
            for sp = SPs
                %Part 4b: Calculating Nodes_u(self_prob_dist, Nodes_var, frequencies, MAFs, Nodes_c) 
                %Last 3 parameter never changes
                %{
                for j = 1:dataSize
                    prob = vars(j,:);
                    Nodes_u(j,2) = {prob};
                    %Apply utility transformation formula (Rework)
                    if freqs(j,personalData(j)+1) == 0 || MAFs(j) == 0
                        u_gain = 1;
                        u_gain2 = 1;
                    else
                        u_gain = log(exp(1-MAFs(j)*MAFs(j)+MAFs(j))+(cos(pi*freqs(j,personalData(j)+1))+1)/2);
                        u_gain2 = log(exp(1-MAFs(j)*MAFs(j)+MAFs(j))+(cos(pi*(1-freqs(j,personalData(j)+1)))+1)/2); %If not actual state
                    end
                    for k = 0:2                           
                        if personalData(j) == k
                            prob(k+1) = prob(k+1) * u_gain;
                        else
                            prob(k+1) = prob(k+1) * u_gain2;
                        end
                    end
                    prob = prob.^(log(exp(1)+sum(corIns(:,1)==j)));
                    prob = prob./norm(prob,1);
                    Nodes_u(j,1) = {prob};
                end
                %}

                %Part 4c: Calculating Nodes_ae (self_prob_dist, Nodes_var, shannonEntropy, MAFs)
                if sp ~= 1 && difPriCoef(difs) ~= 0
                    [atks,results] = calculateAttackDistributionFromVar(vars,sharedDataSoFar,sp,dataSize);
                else
                    atks = vars;
                end
                for j = 1:dataSize
                    Nodes_a(j,2) = {vars(j,:)};
                    Nodes_a{j,3} = sharedDataSoFar(1:sp-1,j);
                end
                for t = 1:dataSize
                    while 1
                        condition1_1 = (vars(t,1)*(1-atks(t,1))*exp(difPriCoef(difs)+err)) >= (atks(t,1)*(1-vars(t,1)));
                        condition1_2 = (vars(t,1)*(1-atks(t,1))*exp(-difPriCoef(difs)-err)) <= (atks(t,1)*(1-vars(t,1)));
                        condition2_1 = (vars(t,2)*(1-atks(t,2))*exp(difPriCoef(difs)+err)) >= (atks(t,2)*(1-vars(t,2)));
                        condition2_2 = (vars(t,2)*(1-atks(t,2))*exp(-difPriCoef(difs)-err)) <= (atks(t,2)*(1-vars(t,2)));
                        condition3_1 = (vars(t,3)*(1-atks(t,3))*exp(difPriCoef(difs))+err) >= (atks(t,3)*(1-vars(t,3)));
                        condition3_2 = (vars(t,3)*(1-atks(t,3))*exp(-difPriCoef(difs)-err)) <= (atks(t,3)*(1-vars(t,3)));
                        cond = [condition1_1 condition1_2 condition2_1 condition2_2 condition3_1 condition3_2];
                        cond(isnan(cond)) = 0;
                        if sum(cond) == 6
                            break;
                        else
                            atks(t,:) = atks(t,:)+vars(t,:);
                            atks(t,:) = atks(t,:)./norm(atks(t,:),1);
                        end
                    end
                    Nodes_a(t,1) = {atks(t,:)};
                end
                wScore = zeros([dataSize 5]);
                for j = 1:dataSize
                    wScore(j,1) = 1 - atks(j,personalData(j)+1);
                end    
                wScore(:,2) = 1:dataSize;
                wScore(:,3:5) = atks;
                wScore = sortrows(wScore,'descend');
                sharedDataSoFar(sp,:) = watermark(personalData, atks, wScore, wlens(w));
                %kullbacks(sp,w) = {calculateCrossEntropies(vars,freqs) - calculateShannonEntropies(vars)};
            end
            
            %*************************************************************************************************
            %Collusion Attack, colabs >= 2
            for c = 1:length(colabs)
                %Show Stage
                [t1,t2,t3] = hms(datetime('now'));
                fprintf('Fam Iteration: %d, W_Length: %d, eDP: %.1f, Colabs: %d, %d:%d:%d\n',famIteration, wlens(w), difPriCoef(difs), colabs(c), t1, t2, round(t3));
                [precisionH,precisionHR] = attackHGeneralized(precisionH,precisionHR,sharedDataSoFar,SPs,wlens,w,colabs,c,vars);
                [precisionE,precisionER] = attackEGeneralized(precisionE,precisionER,sharedDataSoFar,SPs,wlens,w,colabs,c,vars);
                precisionH(c,w)  = 100.*precisionH(c,w)./((length(SPs)*(length(SPs)-1)/2)); %Number of all pairs is given in the formula's denominator
                precisionHR(c,w) = 100.*precisionHR(c,w)./((length(SPs)*(length(SPs)-1)/2)); %Number of all pairs is given in the formula's denominator
                precisionE(c,w)  = 100.*precisionE(c,w)./((length(SPs)*(length(SPs)-1)/2)); %Number of all pairs is given in the formula's denominator
                precisionER(c,w) = 100.*precisionER(c,w)./((length(SPs)*(length(SPs)-1)/2)); %Number of all pairs is given in the formula's denominator
            end   
        end
        %save(['results/Utility_w10rr08.mat'],'utilityScores'); %num2str(ceil(ldp_wl_ratio(ldp)*10)) '.mat'],'utilityScores');
        %p1_01(ldp,:) = [precisionE precisionER precisionH precisionHR];
        p1_01(((difs-1)*length(colabs)+1):((difs-1)*length(colabs)+length(colabs)),:) = [precisionE precisionER precisionH precisionHR];
    end
    allResults = allResults + p1_01;
    %save(['results/fam/p1_01_fam' num2str(famIteration) '.mat'],'p1_01');
end
allResults = allResults./length(families);
clear t1 t2 t3 file filename famNodeNum famIteration dataSize aa kids h mods numIterations 
clear patternThreshold sp SPs totalSharingEstimated watermarkLength wlens fgroupNum
clear cNum graph final_mssg corr_mssg prob pheSize aInt
clear i y cldp k temp temp2 rr m t ratio j repeat w a x families
clear pheIs pheIsA famIsA correlations frequencies
clear v1 v2 v3 v4 difPriCoef u_gain u_gain2 ldp_wl_ratio c colabs ldp
%clear precisionE precisionER precisionH precisionHR