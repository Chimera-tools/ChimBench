#!/bin/bash

# ChimBench.sh
# Script that provides several numbers to assess sensitivity (sn) and precision (pr) of a program that 
# produces chimeric junctions (from rnaseq) of a sample with respect to a list of reference junctions known 
# to be present (in the same sample)
# Here the assessment is both done at the junction level and at the gene level, but the gene overlap
# is computed inside the script, meaning that only junction coordinates have to be provided
# note that we only consider junctions where each part overlaps an exon, otherwise they are discarded
# Takes as input:
#################
# - a file with header which 1st column corresponds to the ids of the chimeric junctions that need to be detected (reference) 
#   (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
# - a file with header which 1st column corresponds to the chimeric junctions that are predicted by a program 
#   (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
# - a file with the gene annotation in gff 2 format with at least exon rows and with gene_id and transcript_id as first two
#   (key,value) pairs in the 9th field
# Provides:
###########
# - on the standard output tabulated information with the number junctions in each file, the number of junctions in common, the number of junctions that are 
#   in one and not in the other and a sensitivity and a precision measure (although for positive sets this precision is an underestimate of the true one 
#   since we do not know whether there are other chimeras to be found in this set)
# - a 1 column file called common.txt with the coordinates of the common chimeric junctions 
# - a 2 column tsv file called refjunc_closestpred.tsv with the reference junctions which have a close predicted junction (1st col = ref; 2nd col = close)
# - a file with the predicted junctions (same as 2nd input file) but with information about all the reference junctions sharing the same chr and strand
#   for the two parts of the junction, their donor distance to the predicted junction don, their acceptor distance to the predicted junction acc
#   the sum of those and the subset of sums that are minimum together with their associated reference junctions
# - other intermediate gff and tsv files

# usage
#######
# ChimBench.sh ref_junctions.txt pred_junctions.txt annot.gff > report.tsv 2> benchmark_chimeric_junction_better.err


# To improve
############
# - make a complete annot from only exons rows so that it has gene rows as well and then can put back if($3=="gene") when reading the annot, twice down
#   this will avoid to read all exons for a gene to info about the gene 
# - make an ok file from the annotation, allowing to have gene_id and transcript_id to be anywhere in the 9th field of the annotation file
# - add benchmark for each of the 5 classes of chimeras: readthrough, intrachromosomal, inverted, interstrand, interchromosomal
#   (based on distance between donor and acceptor sites for the 2 first classes)

# example
#########
# cd /no_backup/rg/sdjebali/Chimeras/ChimPipe/benchmark/ChimPipe-0.9.1/Edgren/pooled/Final
# ref=/users/rg/sdjebali/Chimeras/Benchmark/Data/Edgren/DoneByBR_Blat/Edgren_juncid_gnname_ss_sample.tsv 
# annot=/users/rg/projects/encode/scaling_up/whole_genome/Gencode/version19/Long/gencode.v19.annotation.long.gtf
# time ChimBench.sh $ref ../chimericJunctions_pooled.txt $annot > benchmark_report.tsv 2> benchmark_chimeric_junction_better.err &
# real    0m23.777s

# main output is this summary
# ref     42
# pred    116
# common  35
# ref_not_in_common       7
# pred_not_in_common      81
# sensitivity     83.3333
# precision       30.1724
# close25nt_not_exact     0
# samechrstr      70
# refgn   37
# predgn  88
# commongn        34
# refgn_not_in_commongn   3
# predgn_not_in_commongn  54
# sngn    91.8919
# precgn  38.6364
# commongn2       0
# sum_don_acc_dist        0.0:0.0:0.0:254.9:0.0:8444.0

# Check the input files and if OK assign to variables
#####################################################
if [ ! -e "$1" ] || [ ! -e "$2" ] || [ ! -e "$3" ]
then
    echo "" >&2
    echo USAGE: >&2
    echo "" >&2
    echo "ChimBench.sh ref_junctions.txt pred_junctions.txt annot.gff" >&2
    echo "" >&2
    echo "Takes as input:" >&2
    echo "- a file with header which 1st column corresponds to ids of chimeric junctions that need to be detected (reference) (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)" >&2
    echo "- a file with header which 1st column corresponds to chimeric junctions that are predicted by a program (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)" >&2
    echo "- a gff version 2 or gtf file with the annotated exons (and more) and where gene_id and transcript_id are the 1st two (key,value) pairs in the 9th field" >&2
    echo "" >&2
    echo "Provides:" >&2
    echo "- on the standard output tabulated information with the number junctions in each file, the number of junctions in common, the number of junctions that are" >&2
    echo "  in one and not in the other and a sensitivity and a precision measure (although for positive sets this precision is an underestimate of the true one" >&2
    echo "  since we do not know whether there are other chimeras to be found in this set)" >&2
    echo "- a 1 column file called common.txt with the coordinates of the common chimeric junctions" >&2
    echo "- an 8 column tsv file called ref_junc_belonging_to_common_gnpairs_vs_pred_same.tsv with the predicted junctions (same as 2nd input file) but" >&2 
    echo "  with information about all the reference junctions sharing the same chr and strand for the two parts of the junction, their donor distance" >&2  
    echo "  to the predicted junction donor, their acceptor distance to the predicted junction acceptor, the sum of those and the subset of sums that" >&2  
    echo "  are minimum together with their associated reference junctions"
    echo "- other intermediate gff and tsv files"
    echo "NOTE: cannot be run twice in the same directory without loosing previous outputs since uses fixed names for outputs" >&2  
    echo "" >&2
    exit 1
else
    ref=$1
    pred=$2
    annot=$3
fi

path="`dirname \"$0\"`" # relative path
rootDir="`( cd \"$path\" && pwd )`" # absolute path

# Programs and scripts
######################
ChimToGff=$rootDir/../Awk/chim_txt_to_gff_ssext.awk
GFF2GFF=$rootDir/../Awk/gff2gff.awk
OVER=$rootDir/../bin/overlap
RMRND=$rootDir/../Awk/remove_redund_better.awk
COMP=$rootDir/../Awk/compare_chim_junc.awk
CUTGFF=$rootDir/../Awk/cutgff.awk
MNSD=$rootDir/../Awk/mean_sd.awk
STATS=$rootDir/stats.sh

##############################
# Junction level evaluation  #
##############################

# Compute basic numbers and print junctions that are exactly identical
######################################################################
refno=`awk 'NR>=2{print $1}' $ref | sort | uniq | wc -l | awk '{print $1}'`
predno=`awk 'NR>=2{print $1}' $pred | sort | uniq | wc -l | awk '{print $1}'`

cat $ref $pred | awk '{print $1}' | sort | uniq -c | awk '$1==2&&$2~/:/{print $2}' > common.txt
common=`wc -l common.txt | awk '{print $1}'`

sn=`echo $common $refno | awk '{print ($1/$2)*100}'`
pr=`echo $common $predno | awk '{print ($1/$2)*100}'`

# Find the junctions which two sides overlap but that are not exact
###################################################################
# do not consider junctions where some coord are unknown
########################################################
# difference with previous script is that we extend by 50 bp on each side, instead of 25 bp
###########################################################################################
# !!! here no need to substract the header since already done by $ChimToGff !!!
awk '$1!~/NA/' $ref | awk -v ext=50 -f $ChimToGff | awk -f $GFF2GFF > ref.gff
awk '$1!~/NA/' $pred | awk -v ext=50 -f $ChimToGff | awk -f $GFF2GFF > pred.gff
$OVER ref.gff pred.gff -st 1 -f pred -m 10 -nr -o ref_over_pred.gff
awk '$NF!="."{split($10,a,"\""); gsub(/\"/,"",$NF); gsub(/\;/,"",$NF); list[a[2]]=(list[a[2]])($NF)}END{for(j in list){print j, list[j]}}' ref_over_pred.gff | awk -v fldlist=junc:2 -f $RMRND | awk '{found=""; split($(NF-2),a,","); k=1; while(a[k]!=""){split(a[k],b,":"); if(b[3]==2){found=(found)","(b[1]":"b[2])} k++} if(found!=""){gsub(/\,/,"\t",found); print $1"\t"found}}' | awk '$1!=$2' > refjunc_closepred.tsv
close=`wc -l refjunc_closepred.tsv | awk '{print $1}'`

# For each predicted junction, report the list of reference junctions that have the same chr and strand
#######################################################################################################
# as the predicted one on both sides, together with the distances between the predicted and the reference
#########################################################################################################
# splice sites for each part of the junction, as well as the sum of those distances, and at the end
###################################################################################################
# put either the reference junction that minimizes both the donor and the acceptor distance, or if it
#####################################################################################################
# does not exist, put the one that minimizes the sum of those distances (if there are many put the list of them)
################################################################################################################
awk -v fileRef=$ref -f $COMP $pred > pred_vs_ref.tsv
close2=`awk '$NF!="."' pred_vs_ref.tsv | wc -l`

printf "ref\t$refno\n"
printf "pred\t$predno\n"
printf "common\t$common\n"
printf "ref_not_in_common\t"$((refno-common))"\n"
printf "pred_not_in_common\t"$((predno-common))"\n"
printf "sensitivity\t$sn\n"
printf "precision\t$pr\n"
printf "close25nt_not_exact\t"$close"\n"
printf "samechrstr\t"$close2"\n"


###########################
# Gene level evaluation   #
###########################
awk '$3=="exon"' $annot | awk -v to=12 -f $CUTGFF | awk -f $GFF2GFF > exons_cut12.gff
# chr1  HAVANA  exon    11869   12227   .       +       .       gene_id "ENSG00000223972.4"; transcript_id "ENST00000456328.2";
# 1187120 (12 fields)

# Reference
###########
# Compare the two parts of the junctions to exons and report the most likely gene on each side
##############################################################################################
# !!! most likely is determined based on the number of exons of the gene, the more the better !!!
# !!! this strategy is for sure less sophisticated than what is done in chimpipe and may leas to different answers !!!
$OVER ref.gff exons_cut12.gff -m -1 -nr -f ex -v | awk -v fileRef=exons_cut12.gff 'BEGIN{while (getline < fileRef >0){split($10,a,"\""); gnlist[$1"_"$4"_"$5"_"$7]=(gnlist[$1"_"$4"_"$5"_"$7])(a[2])(",")}} {s=""; split($NF,a,","); k=1; while(a[k]!=""){s=(s)(gnlist[a[k]])(","); k++} gsub(/,,/,",",s); print $0, "gnlist:", s}'  | awk -f $GFF2GFF | awk -v fldlist=gnlist:16 -f $RMRND | awk -v fileRef=exons_cut12.gff 'BEGIN{while (getline < fileRef >0){split($10,a,"\""); nbex[a[2]]++}} {n=split($18,a,","); split(a[1],b,":"); gn=b[1]; k=2; while(a[k]!=""){split(a[k],b,":"); if(nbex[b[1]]>nbex[gn]){gn=b[1]} k++} print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $13, $14, $17, $18, "bestgn:", gn}' | awk -f $GFF2GFF > ref_over_ex_withgnids_woredund_bestgn.gff
# chr1  .       fivep   247094880       247094905       .       -       .       junc_id "chr1_247094880_-:chr4_76846964_-"; list_ex: chr1_247094880_247095280_-, gnlist_nr: ENSG00000153207.10:1, bestgn: ENSG00000153207.10
# 82 (16 fields)
# Put together the two parts of the junction and add the gene names after the two gene ids
##########################################################################################
# removed if($3=="gene"){} on jan22nd2016 because some annot do not have it but if we make a complete one and also ok from start could reput (saves time)
# replaced by if(nb[$10]==1){ to save time but should be done in a better way
awk -v fileRef=$annot 'BEGIN{OFS="\t"; while (getline < fileRef >0){nb[$10]++; if(nb[$10]==1){split($0,a,"\t"); split(a[9],b,"; "); k=1; while(b[k]!=""){split(b[k],c," "); if(c[1]=="gene_id"){split(c[2],d,"\""); gnid=d[2]}else{if(c[1]=="gene_name"){split(c[2],d,"\""); gnname=d[2]}} k++}} name[gnid]=gnname}} {split($10,a,"\""); if($3=="fivep"){fivepgn[a[2]]=$16}else{threepgn[a[2]]=$16}} END{for(j in fivepgn){print j, fivepgn[j], threepgn[j], name[fivepgn[j]], name[threepgn[j]]}}' ref_over_ex_withgnids_woredund_bestgn.gff > ref_gnid_gnname.tsv
# chr17_38465538_+:chr8_79485046_+      ENSG00000131759.13      ENSG00000171033.8       RARA    PKIA
# 41 (5 fields)

# Predictions
#############
# Compare the two parts of the junctions to exons and report the most likely gene on each side
##############################################################################################
# !!! most likely is determined based on the number of exons of the gene, the more the better !!!
# !!! this strategy is for sure less sophisticated than what is done in chimpipe and may leas to different answers !!!
$OVER pred.gff exons_cut12.gff -m -1 -nr -f ex -v | awk -v fileRef=exons_cut12.gff 'BEGIN{while (getline < fileRef >0){split($10,a,"\""); gnlist[$1"_"$4"_"$5"_"$7]=(gnlist[$1"_"$4"_"$5"_"$7])(a[2])(",")}} {s=""; split($NF,a,","); k=1; while(a[k]!=""){s=(s)(gnlist[a[k]])(","); k++} gsub(/,,/,",",s); print $0, "gnlist:", s}'  | awk -f $GFF2GFF | awk -v fldlist=gnlist:16 -f ~/Awk/remove_redund_better.awk | awk -v fileRef=exons_cut12.gff 'BEGIN{while (getline < fileRef >0){split($10,a,"\""); nbex[a[2]]++}} {n=split($18,a,","); split(a[1],b,":"); gn=b[1]; k=2; while(a[k]!=""){split(a[k],b,":"); if(nbex[b[1]]>nbex[gn]){gn=b[1]} k++} print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $13, $14, $17, $18, "bestgn:", gn}' | awk -f $GFF2GFF > pred_over_ex_withgnids_woredund_bestgn.gff
# chr1  .       threep  11740620        11740670        .       -       .       junc_id "chr1_11751809_-:chr1_11740670_-"; list_ex: chr1_11740410_11740670_-,chr1_11740619_11740670_-,chr1_11740619_11741188_-, gnlist_nr: ENSG00000116670.10:9, bestgn: ENSG00000116670.10
# 230 (16 fields)
# Put together the two parts of the junction and add the gene names after the two gene ids
##########################################################################################
# removed if($3=="gene"){} on jan22nd2016 because some annot do not have it but if we make a complete one and also ok from start could reput (saves time)
# replaced by if(nb[$10]==1){ to save time but should be done in a better way
awk -v fileRef=$annot 'BEGIN{OFS="\t"; while (getline < fileRef >0){nb[$10]++; if(nb[$10]==1){split($0,a,"\t"); split(a[9],b,"; "); k=1; while(b[k]!=""){split(b[k],c," "); if(c[1]=="gene_id"){split(c[2],d,"\""); gnid=d[2]}else{if(c[1]=="gene_name"){split(c[2],d,"\""); gnname=d[2]}} k++}} name[gnid]=gnname}} {split($10,a,"\""); if($3=="fivep"){fivepgn[a[2]]=$16}else{threepgn[a[2]]=$16}} END{for(j in fivepgn){print j, fivepgn[j], threepgn[j], name[fivepgn[j]], name[threepgn[j]]}}' pred_over_ex_withgnids_woredund_bestgn.gff > pred_gnid_gnname.tsv
# chr17_38465538_+:chr8_79485046_+      ENSG00000131759.13      ENSG00000171033.8       RARA    PKIA
# 115 (5 fields)


# Compute the number of common gene pairs for which the order is correct
########################################################################
awk '{print $4":"$5}' ref_gnid_gnname.tsv | sort | uniq > ref_gnpairs.txt
refgn=`wc -l ref_gnpairs.txt | awk '{print $1}'`
awk '{print $4":"$5}' pred_gnid_gnname.tsv | sort | uniq > pred_gnpairs.txt
predgn=`wc -l pred_gnpairs.txt | awk '{print $1}'`
cat ref_gnpairs.txt pred_gnpairs.txt | sort | uniq -c | awk '$1==2{print $2}' > common_gnpairs.txt
# AC099850.1:VMP1
# 34 (1 fields)
commongn=`wc -l common_gnpairs.txt | awk '{print $1}'`
# Compute the number of common gene pairs for which the order is incorrect
##########################################################################
awk '{print $5":"$4}' pred_gnid_gnname.tsv | sort | uniq > pred_gnpairs_koorder.txt
commongn2=`cat ref_gnpairs.txt pred_gnpairs_koorder.txt | sort | uniq -c | awk '$1==2' | wc -l | awk '{print $1}'`

# Compute Sn and precision out of the common order gene pairs 
##############################################################
sngn=`echo $commongn $refgn | awk '{print ($1/$2)*100}'`
prgn=`echo $commongn $predgn | awk '{print ($1/$2)*100}'`

# Print the gene level evaluation
#################################
printf "refgn\t$refgn\n"
printf "predgn\t$predgn\n"
printf "commongn\t$commongn\n"
printf "refgn_not_in_commongn\t"$((refgn-commongn))"\n"
printf "predgn_not_in_commongn\t"$((predgn-commongn))"\n"
printf "sngn\t$sngn\n"
printf "precgn\t$prgn\n"
printf "commongn2\t$commongn2\n"


# Donor + acceptor distance for junctions in common gene pairs in correct order
###############################################################################
# Make the reference junctions belonging to the common gene pairs in correct order
##################################################################################
awk -v fileRef=common_gnpairs.txt 'BEGIN{OFS="\t"; print "juncid"; while (getline < fileRef >0){ok[$1]=1}} ok[$4":"$5]==1{print $1}' ref_gnid_gnname.tsv > ref_junc_belonging_to_common_gnpairs.txt
# juncid
# chr17_38465538_+:chr8_79485046_+
# 39 (1 fields)  
# Make the predicted junctions belonging to the common gene pairs in correct order
##################################################################################
awk -v fileRef=common_gnpairs.txt 'BEGIN{OFS="\t"; print "juncid"; while (getline < fileRef >0){ok[$1]=1}} ok[$4":"$5]==1{print $1}' pred_gnid_gnname.tsv > pred_junc_belonging_to_common_gnpairs.txt
# juncid
# chr17_38465538_+:chr8_79485046_+
# 53 (1 fields)   *** even more multiplicity of junctions for a given gene pair
# Compare the pred to the ref junctions just for those in common and correct order gene pairs and add the gene names
####################################################################################################################
# note that the comparison script is here used in the reverse order wrt above
#############################################################################
awk -v fileRef=pred_junc_belonging_to_common_gnpairs.txt -f $COMP ref_junc_belonging_to_common_gnpairs.txt | awk -v fileRef=ref_gnid_gnname.tsv 'BEGIN{OFS="\t"; while (getline < fileRef >0){gnpair[$1]=$4":"$5}} NR==1{print $0, "gnpair"}NR>=2{print $0, gnpair[$1]}' > ref_junc_belonging_to_common_gnpairs_vs_pred_same.tsv
# juncid        refjunc dondist accdist sumdist bestdist        bestref gnpair
# chr17_38465538_+:chr8_79485046_+        chr17_38465538_+:chr8_79485046_+,chr17_38465538_+:chr8_79510593_+,      0,0,    0,25547,        0,25547,        0,      chr17_38465538_+:chr8_79485046_+,  RARA:PKIA
# 39 (8 fields)  *** be careful here not only the min junc will be provided but the 1st one as well as all between 1st and the min that are in decreasing order so need to print at the end in $COMP (but because of several possible not easy to modify)
# Use these results to report for each common gene pair the junction with the min (dondist+accdist)
###################################################################################################
awk 'BEGIN{OFS="\t"; print "dongn", "accgn", "bestjunc", "bestdist"} NR>=2{refjunclist[$8]=(refjunclist[$8])($1)(","); bestjunclist[$8]=(bestjunclist[$8])($7)(","); bestdistlist[$8]=(bestdistlist[$8])($6)(",")} END{for(gp in refjunclist){split(gp,a,":"); gsub(/,,/,",",refjunclist[gp]); gsub(/,,/,",",bestjunclist[gp]); gsub(/,,/,",",bestdistlist[gp]); split(bestjunclist[gp],b,","); split(bestdistlist[gp],c,","); k=1; m=4000000000; while(b[k]!=""){if(c[k]<m){m=c[k]; j=b[k]} k++} print a[1], a[2], j, m}}' ref_junc_belonging_to_common_gnpairs_vs_pred_same.tsv > dongn_accgn_bestjunc_bestdist.tsv
# dongn accgn   bestjunc        bestdist
# MED13   BCAS3   chr17_60129898_-:chr17_59469338_+       0
# 35 (4 fields)  

# Print the distribution of the sum of the donor and acceptor distances
#######################################################################
awk 'NR>=2&&$4!="."{print $4}' dongn_accgn_bestjunc_bestdist.tsv > tmp.txt
nb=`awk 'NR>=2{n++}END{print n}' dongn_accgn_bestjunc_bestdist.tsv`
mn=`awk -f $MNSD tmp.txt | awk '{print $1}'`
sd=`awk -f $MNSD tmp.txt | awk '{print $2}'`
$STATS tmp.txt | awk -v nb=$nb -v mn=$mn -v sd=$sd 'NR==3{print "sum_don_acc_dist\t"$2":"$3":"$4":"$5":"$6":"$7":"nb":"mn":"sd}'

# Clean
########
# rm ref.gff pred.gff
rm exons_cut12.gff
rm tmp.txt
