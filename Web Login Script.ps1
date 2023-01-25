$username = "username" 
$password = "password" 
$url="https://register.msi.com/home/login?ref=reward/dashboard"

$ie = New-Object -com InternetExplorer.Application 
$ie.visible=$false
$ie.navigate("Url")
 
while($ie.ReadyState -ne 4) {start-sleep -m 100} 
#You need to go to the page and check the ID of the tag containting the textbox where you are going to put the username and change the "username" for the "valueintheIdintheTag"
$ie.document.getElementById("username").value= "$username" 
#same procedure, find the id of the textbox for the password
$ie.document.getElementById("pass").value = "$password" 
#same procedure, find the id of the Sumit button in the web
$ie.document.getElementById("loginform").submit()
start-sleep 20 
$ie.Document.body | Out-File -FilePath c:\web.txt 