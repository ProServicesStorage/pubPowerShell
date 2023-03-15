# Change Mount Paths in bulk. 
# IHAC that has a disk library with 50+ mount paths. I want to update the share settings so that the alternate MAs only have Read access, not Read/Write
# Types are 4 for read, 6 for read/write, 14 for read/write/preferred
# Usage ./set-cvmount.ps1 -libraryName MyLibrary -inputfile c:\scripts\listofmounts.txt -mediaAgent myMA -type 4
# The input file should be one mount path per line. 


param ([String] $libraryName, [String] $inputfile, [String] $mediaAgent, [int] $type )
#Types are 4 for read, 6 for read/write, 14 for read/write/preferred

$mountpathArray = Get-Content -Path $inputFile

foreach ($mountpath in $mountpathArray)

{
    
    #Generate XML 
	$TmpXML = "<EVGui_ConfigureStorageLibraryReq>
	<library libraryName=`"$libraryName`" mediaAgentName=`"$mediaAgent`" mountPath=`"$mountPath`" opType=`"8`"/>
	<libNewProp deviceAccessType=`"$type`" mountPath=`"$mountPath`"/>
	</EVGui_ConfigureStorageLibraryReq>
	"
    #Create temporary XML file for qoperation
	$tmpXmlFile = [System.IO.Path]::GetTempFileName()			
	$TmpXML | Set-Content $tmpXmlFile
	qoperation execute -af $tmpXmlFile
    #cleanup
	Remove-Item $tmpXmlFile

}
