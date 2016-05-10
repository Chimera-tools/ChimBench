# ChimBench
**Benchmark a set of predicted chimeric exonic junctions with respect to a set of reference chimeric exonic junctions**

From a set of reference chimeric exonic junctions, a set of predicted chimeric exonic junctions, and an underlying annotation, produces a report including sensitivity and precision of the predicted set with respect to the reference set, both at the junction and at the gene level, together with other useful numbers and files.

To clone the repository do:
git clone https://github.com/Chimera-tools/ChimBench.git

Running Bash/benchmark_chimeric_junction_better.sh will provide usage

USAGE:

benchmark_chimeric_junction_better.sh ref_junctions.txt pred_junctions.txt annot.gff

Takes as input:
- a file with header which 1st column corresponds to ids of chimeric junctions that need to be detected (reference) (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
- a file with header which 1st column corresponds to chimeric junctions that are predicted by a program (in the chimpipe format: donchr_donpos_donstrand:accchr_accpos_accstrand)
- a gff version 2 or gtf file with the gene annotation, that has at least exon rows and where gene_id and transcript_id are the 1st two (key,value) pairs in the 9th field

Provides:
- on the standard output tabulated information with the number junctions in each file, the number of junctions in common, the number of junctions that are in one and not in the other and a sensitivity and a precision measure (although for positive sets this precision is an underestimate of the true one since we do not know whether there are other chimeras to be found in this set)
- a 1 column file called common.txt with the coordinates of the common chimeric junctions

