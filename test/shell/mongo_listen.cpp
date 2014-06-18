#include <iostream>
#include <iomanip>
#include <unistd.h>

#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

using namespace std;

int listenSockFd = 0;
int clientSockFd = 0;

#define CLIENT_MAX_LINE 4096

void perrorAndExit( string s ) {
    perror(s.c_str());
    exit(1);
}

int listenSocketSetup( int portNumber ) {
    int listenSockFd = socket(AF_INET, SOCK_STREAM, 0);
    if (listenSockFd < 0)
        perrorAndExit("Error on socket create for listening");
    struct sockaddr_in serverAddress;
    bzero((char *) &serverAddress, sizeof(serverAddress));
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_addr.s_addr = INADDR_ANY;
    serverAddress.sin_port = htons(portNumber);
    if (bind(listenSockFd, (struct sockaddr *) &serverAddress, sizeof(serverAddress)) < 0)
        perrorAndExit("Error on socket bind for listening");
    return listenSockFd;
}

int acceptSocket( int listenSockFd ) {
    fprintf(stderr, "listening...\n");
    listen(listenSockFd, 5);
    struct sockaddr_in clientAddress;
    socklen_t clientAddressLen = sizeof(clientAddress);
    int clientSockFd = accept(listenSockFd, (struct sockaddr *)&clientAddress, &clientAddressLen);
    if (clientSockFd < 0)
        perrorAndExit("Error on socket accept");
    fprintf(stderr, "accepted.\n");
    int ret = dup2(clientSockFd, fileno(stdout));
    if (ret < 0)
        perrorAndExit("Error on socket dup to standard out");
    return clientSockFd;
}

char * chomp( char * line ) {
    int count = strlen(line);
    while ( --count >= 0 && (line[count] == '\n' || line[count] == '\r') )
        line[count] = '\0';
    return line;
}

char * shellReadline( const char * prompt , int handlesigint = 0 ) {
    char buffer[CLIENT_MAX_LINE];
    while ( 1 ) {
        if (!clientSockFd)
            clientSockFd = acceptSocket(listenSockFd);
        write(clientSockFd, prompt, strlen(prompt));
        fprintf(stderr, "reading...\n");
        int n = read(clientSockFd, buffer, CLIENT_MAX_LINE - 1);
        if (n > 0) {
            buffer[n] = '\0';
            chomp(buffer);
            return strdup(buffer);
        }
        else if (n < 0)
            perror("Error on socket read");
        else
            fprintf(stderr, "Zero length socket read\n");
        close(clientSockFd);
        clientSockFd = 0;
    }
}

int main( int argc, char *argv[] )
{
    int listenPortNumber = 5001;
    listenSockFd = listenSocketSetup(listenPortNumber);
    cout << "listening on port " << listenPortNumber << endl;

    while ( 1 ) {
        char buffer[CLIENT_MAX_LINE];
        string prompt = "> ";
        char * line = shellReadline(prompt.c_str());
        fprintf(stderr, "message read: %s\n", line);
        sprintf(buffer, "server received message: \"%s\"\n", line);
        ssize_t n = write(clientSockFd, buffer, strlen(buffer));
        if (n < 0)
            perror("ERROR writing to socket");
        free(line);
    }
    return 0;
}
