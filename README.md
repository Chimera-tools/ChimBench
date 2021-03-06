# ChimBench
**Benchmark a set of predicted chimeric junctions with respect to a set of reference chimeric junctions**

From a set of reference chimeric exonic junctions, a set of predicted chimeric exonic junctions, and an underlying annotation, produces a report including sensitivity and precision of the predicted set with respect to the reference set, both at the junction and at the gene level, together with other useful numbers and files.

To clone the repository do:
git clone https://github.com/Chimera-tools/ChimBench.git

Running Bash/ChimBench.sh will provide usage

USAGE:

ChimBench.sh ref_junctions.txt pred_junctions.txt annot.gff

Takes as input:
- a file with header which 1st column corresponds to ids of chimeric junctions that need to be detected (reference) (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
- a file with header which 1st column corresponds to chimeric junctions that are predicted by a program (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
- a gff version 2 or gtf file with the gene annotation, that has at least exon rows and where gene_id and transcript_id are the 1st two (key,value) pairs in the 9th field

Provides:
- on the standard output tabulated information with the number junctions in each file, the number of junctions in common, the number of junctions that are in one and not in the other and a sensitivity and a precision measure (although for positive sets this precision is an underestimate of the true one since we do not know whether there are other chimeras to be found in this set)
- a 1 column file called common.txt with the coordinates of the common chimeric junctions
- an 8 column tsv file called ref_junc_belonging_to_common_gnpairs_vs_pred_same.tsv with the predicted junctions (same as 2nd input file) but with information about all the reference junctions sharing the same chromosome and strand for the two parts of the junction, their donor distance to the predicted junction donor, their acceptor distance to the predicted junction acceptor, the sum of those and the subset of sums that are minimum together with their associated reference junctions
- other intermediate gff and tsv files

NOTE: cannot be run twice in the same directory without loosing previous outputs since uses fixed names for outputs 
